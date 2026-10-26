// SidecarClient：以子进程启动 Node sidecar，经 stdin/stdout 走行分隔 JSON-RPC；App 退出时关闭 stdin，sidecar 随之退出。
import Foundation
import os

struct RPCError: Error, LocalizedError {
    let code: Int
    let message: String
    /// catbus 错误码（如 RISK_CONTROL、AUTH_REQUIRED），非 catbus 错误为 nil。
    let appCode: String?
    let hint: String?

    var errorDescription: String? { hint.map { "\(message)（\($0)）" } ?? message }
}

enum SidecarError: Error, LocalizedError {
    case nodeNotFound
    case sidecarNotFound(String)
    case notRunning
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .nodeNotFound: return "找不到 Node（需要 Node 26+）。可设置环境变量 CATLAND_NODE 指定路径。"
        case .sidecarNotFound(let p): return "找不到 sidecar：\(p)"
        case .notRunning: return "本地服务未运行"
        case .decode(let m): return "数据解析失败：\(m)"
        }
    }
}

final class SidecarClient: @unchecked Sendable {
    typealias NotificationHandler = @Sendable (_ method: String, _ params: Data) -> Void

    private let log = Logger(subsystem: "app.catland", category: "sidecar")
    private let queue = DispatchQueue(label: "app.catland.sidecar")
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextId = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var onNotification: NotificationHandler?
    private let decoder = JSONDecoder()

    func setNotificationHandler(_ handler: @escaping NotificationHandler) {
        queue.sync { onNotification = handler }
    }

    func start() throws {
        let node = try Self.findNode()
        let dir = try Self.sidecarDir()
        let main = dir.appendingPathComponent("src/main.ts")
        guard FileManager.default.fileExists(atPath: main.path) else { throw SidecarError.sidecarNotFound(main.path) }

        let p = Process()
        p.executableURL = node
        p.arguments = [main.path]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [node.deletingLastPathComponent().path, env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if !data.isEmpty, let s = String(data: data, encoding: .utf8) { self?.log.debug("sidecar stderr: \(s, privacy: .public)") }
        }
        p.terminationHandler = { [weak self] proc in
            self?.log.error("sidecar exited: \(proc.terminationStatus)")
            self?.queue.async { self?.failAll(SidecarError.notRunning) }
        }
        try p.run()
        process = p
        stdin = inPipe.fileHandleForWriting
        log.info("sidecar started pid=\(p.processIdentifier) node=\(node.path, privacy: .public)")
    }

    func stop() {
        try? stdin?.close()
        process = nil
    }

    /// 调用 RPC 方法并解码结果。
    func call<T: Decodable>(_ method: String, _ params: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await callRaw(method, params)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            log.error("decode \(method, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw SidecarError.decode("\(method): \(error)")
        }
    }

    func callRaw(_ method: String, _ params: [String: Any] = [:]) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async { [self] in
                guard let stdin else { return cont.resume(throwing: SidecarError.notRunning) }
                nextId += 1
                let id = nextId
                let msg: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
                guard var line = try? JSONSerialization.data(withJSONObject: msg) else {
                    return cont.resume(throwing: SidecarError.decode("cannot encode params for \(method)"))
                }
                line.append(0x0A)
                pending[id] = cont
                do { try stdin.write(contentsOf: line) } catch {
                    pending.removeValue(forKey: id)
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty else { continue }
            handle(Data(line))
        }
    }

    private func handle(_ line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            log.error("non-JSON line from sidecar")
            return
        }
        if let id = obj["id"] as? Int, let cont = pending.removeValue(forKey: id) {
            if let err = obj["error"] as? [String: Any] {
                let data = err["data"] as? [String: Any]
                cont.resume(throwing: RPCError(code: err["code"] as? Int ?? -1, message: err["message"] as? String ?? "error",
                                               appCode: data?["code"] as? String, hint: data?["hint"] as? String))
            } else {
                let result = obj["result"] ?? NSNull()
                cont.resume(returning: (try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])) ?? Data("null".utf8))
            }
        } else if let method = obj["method"] as? String {
            let params = (try? JSONSerialization.data(withJSONObject: obj["params"] ?? NSNull(), options: [.fragmentsAllowed])) ?? Data()
            onNotification?(method, params)
        }
    }

    private func failAll(_ error: Error) {
        let conts = pending
        pending.removeAll()
        stdin = nil
        conts.values.forEach { $0.resume(throwing: error) }
    }

    // MARK: - 定位 Node 与 sidecar

    static func findNode() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        var candidates = [env["CATLAND_NODE"]].compactMap { $0 }
        if let bundled = Bundle.main.url(forResource: "node", withExtension: nil, subdirectory: "sidecar/bin") { candidates.append(bundled.path) }
        candidates += ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(NSHomeDirectory())/.volta/bin/node"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        throw SidecarError.nodeNotFound
    }

    static func sidecarDir() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["CATLAND_SIDECAR_DIR"] { return URL(fileURLWithPath: env) }
        if let bundled = Bundle.main.url(forResource: "sidecar", withExtension: nil) { return bundled }
        if let dev = Bundle.main.object(forInfoDictionaryKey: "CatlandSidecarDir") as? String, !dev.isEmpty {
            return URL(fileURLWithPath: dev).standardizedFileURL
        }
        throw SidecarError.sidecarNotFound("CatlandSidecarDir")
    }
}

extension JSONDecoder {
    static let rpc = JSONDecoder()
}
