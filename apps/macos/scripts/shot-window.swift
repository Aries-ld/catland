// 只截 catland 自己的窗口（不拍其他应用内容）：shot-window <输出.png> [窗口标题包含的文字]
import CoreGraphics
import Foundation

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/catland.png"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let titleFilter = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
let mine = list.filter { (($0[kCGWindowOwnerName as String] as? String) ?? "").lowercased() == "catland" }
    .filter { w in titleFilter.map { ((w[kCGWindowName as String] as? String) ?? "").contains($0) } ?? true }
    .sorted { (($0[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) > (($1[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) }
guard let id = mine.first?[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write("catland window not found\n".data(using: .utf8)!)
    exit(1)
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l", String(id), out]
try p.run()
p.waitUntilExit()
print(out)
