// 调试构建专用：向运行中的 catland 发送界面命令，配合 screencapture 做自动化截图自检。
// 用法：catland-debug <toggle|hover|next|prev|right|pause|comments|connections|settings|saved|close|boss>
import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: catland-debug <command>\n".data(using: .utf8)!)
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(Notification.Name("app.catland.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
