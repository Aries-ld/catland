// 客户端日志落盘：~/Library/Logs/catland/app.log（JSONL，5MB 轮转，保留 3 份），同时写 os_log。
import Foundation
import os

enum AppLog {
    enum Level: String { case debug, info, warn, error }

    private static let queue = DispatchQueue(label: "app.catland.log")
    private static let osLog = Logger(subsystem: "app.catland", category: "app")
    private static let maxBytes = 5 * 1024 * 1024
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/catland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("app.log")
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func debug(_ msg: String, _ ctx: [String: Any] = [:]) { write(.debug, msg, ctx) }
    static func info(_ msg: String, _ ctx: [String: Any] = [:]) { write(.info, msg, ctx) }
    static func warn(_ msg: String, _ ctx: [String: Any] = [:]) { write(.warn, msg, ctx) }
    static func error(_ msg: String, _ ctx: [String: Any] = [:]) { write(.error, msg, ctx) }

    private static func write(_ level: Level, _ msg: String, _ ctx: [String: Any]) {
        #if !DEBUG
        if level == .debug { return }
        #endif
        let date = Date()
        queue.async {
            var obj: [String: Any] = ["ts": iso.string(from: date), "level": level.rawValue, "msg": msg]
            for (k, v) in ctx { obj[k] = JSONSerialization.isValidJSONObject([v]) ? v : String(describing: v) }
            guard var line = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
            line.append(0x0A)
            rotateIfNeeded(adding: line.count)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(line)
                try? h.close()
            } else {
                FileManager.default.createFile(atPath: url.path, contents: line, attributes: [.posixPermissions: 0o600])
            }
        }
        osLog.log(level: level == .error ? .error : (level == .warn ? .default : .info), "\(msg, privacy: .public) \(String(describing: ctx), privacy: .public)")
    }

    private static func rotateIfNeeded(adding n: Int) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size + n > maxBytes else { return }
        for i in stride(from: 2, through: 1, by: -1) {
            let src = url.appendingPathExtension("\(i)"), dst = url.appendingPathExtension("\(i + 1)")
            try? fm.removeItem(at: dst)
            try? fm.moveItem(at: src, to: dst)
        }
        try? fm.moveItem(at: url, to: url.appendingPathExtension("1"))
    }
}
