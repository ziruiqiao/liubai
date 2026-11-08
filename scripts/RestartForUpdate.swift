import AppKit
import Foundation

let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "app.liubai.mac" }
for app in running {
    print("留白 pid=\(app.processIdentifier) path=\(app.bundleURL?.path ?? "unknown")")
}
if CommandLine.arguments.contains("--quit") {
    for app in running where !app.isTerminated {
        guard app.terminate() else { fputs("留白未接受正常退出请求，请先从 App 内退出。\n", stderr); exit(1) }
    }
    let limit = Date().addingTimeInterval(10)
    while running.contains(where: { !$0.isTerminated }) && Date() < limit {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard running.allSatisfy(\.isTerminated) else { fputs("留白尚未退出；未修改正在使用的数据。\n", stderr); exit(1) }
    print("留白已正常退出，退出时的记录由 App 保存。")
}
