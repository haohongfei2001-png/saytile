# 已复现的问题

- 497 每次启动都停在暂停。新设置只在用户选中且曾真正开启收音后记住待命。启动先恢复录音，再检查权限、会话、设备和合盖状态。手动暂停、明确退出和权限撤回取消下一次自动收音。未决定的权限绝不会由自动恢复触发请求。
- 原退出代理对系统及 Sparkle 先回复取消，再发起第二次退出。现使用 AppKit 延迟退出并在草稿、录音与数据库落盘后回复原请求。草稿保存失败时留在原进程。
- #47 会在服务尚未部署时把反馈写入待发队列。签名包现以 Info.plist 内的部署状态控制发送；关闭时允许保存草稿和查看原有记录。明确提交、离线投递与撤回仍在独立注入传输的测试中检查。
- 497 包内的 Sparkle Autoupdate、Updater 及两个 XPC 服务没有 Developer ID 时间戳。0.20 出包须在深层到外层签名后逐一验证，再向 Apple 提交。

分发脚本按 Sparkle 2.10.1 的嵌套签名顺序单独处理两个 XPC 和两个帮助程序，下载进程保留其原有权限。验证时分别检查团队、Hardened Runtime 和安全时间戳。[Sparkle 签名说明](https://sparkle-project.org/documentation/sandboxing/#code-signing)

CI 的 Xcode 26.6 在设置页生成 actor 隔离的 Bool 方法引用包装时触发编译器 SmallVector 崩溃。使用明确的 SwiftUI Binding setter 闭包，并把原有全量 Swift 测试及 localhost 协议服务安排在同一个独立作业。原有测试和断言均保留。Chrome 首次写入时真实 AX 未能稳定读回，两次通知之间第一次观察缺失，现场结果为单次已写入、状态未确认；独立复核中。

## 515 的退出故障

GitHub native 作业在合法隔离探针结束时超时。签名 515 在本机同样超时。采样显示主线程停在 Swift Task 内的 NSApplication.terminate 与 AppKit 的嵌套事件循环，等待的主队列任务无法完成。程序主动退出现在先异步保存、关闭录音和清理窗口，再调用 AppKit。外部退出请求继续获得 AppKit 延迟答复，草稿写入失败仍拒绝退出。使用同一个隔离探针和 Sparkle 安装器复验。打包时对照已签名 497 的资源，避免 iconutil 在无窗口环境下产生不同的图标容器。
