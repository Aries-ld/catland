// ImageLoader：带平台请求头的图片加载 + 内存缓存 + URLCache 磁盘缓存（200MB），供预取与 RemoteImage 使用。
import AppKit
import SwiftUI

@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        memory.countLimit = 300
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 200 << 20, directory: Self.cacheDir())
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
    }

    private static func cacheDir() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("app.catland/images", isDirectory: true)
    }

    func cached(_ src: ImageSource) -> NSImage? { memory.object(forKey: src.url as NSString) }

    func prefetch(_ src: ImageSource) {
        _ = load(src)
    }

    @discardableResult
    func load(_ src: ImageSource) -> Task<NSImage?, Never> {
        if let img = memory.object(forKey: src.url as NSString) { return Task { img } }
        if let t = inflight[src.url] { return t }
        let session = self.session
        let t = Task<NSImage?, Never> { [weak self] in
            guard let url = URL(string: src.url) else { return nil }
            var req = URLRequest(url: url, timeoutInterval: 15)
            src.headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
            let result: (Data, URLResponse)
            do { result = try await session.data(for: req) } catch {
                AppLog.warn("image load failed", ["url": String(src.url.prefix(120)), "err": error.localizedDescription])
                self?.inflight[src.url] = nil
                return nil
            }
            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
            guard status < 400, let img = NSImage(data: result.0) else {
                AppLog.warn("image decode failed", ["url": String(src.url.prefix(120)), "status": status, "bytes": result.0.count, "type": (result.1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""])
                self?.inflight[src.url] = nil
                return nil
            }
            self?.memory.setObject(img, forKey: src.url as NSString)
            self?.inflight[src.url] = nil
            return img
        }
        inflight[src.url] = t
        return t
    }
}

/// 远程图片视图：命中缓存时同步显示（翻页时不闪烁）。
struct RemoteImage: View {
    let source: ImageSource?
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let img = image ?? source.flatMap({ ImageLoader.shared.cached($0) }) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color.white.opacity(0.04))
            }
        }
        .task(id: source?.url) {
            guard let s = source else { return }
            image = ImageLoader.shared.cached(s)
            if image == nil { image = await ImageLoader.shared.load(s).value }
        }
    }
}
