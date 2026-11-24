# Saytile 1.0.1 安装与更新（发行候选）

适用 Apple Silicon Mac、macOS 26 或更新系统。只从 https://saytile.com/ 或 https://github.com/haohongfei2001-png/saytile/releases 获取安装包及 SHA256SUMS.txt。

1. 退出已运行的 Saytile；升级前保留旧 App 和资料备份。
2. 验证下载文件 SHA-256 与该版本 Release 一致，打开 DMG，把 Saytile.app 拖到原安装位置。不要从 DMG 内长期运行。
3. 首次打开会显示一次本机识别准备页面。阅读说明、查看模型进度，再点击语音板右下角开始；此时才请求麦克风权限。只有直接输入其他应用时需要辅助功能权限；复制、档案和自由记录不需要。
4. 首次联网准备约 713 MB Qwen 模型。设置中可查看进度；准备期间尝试系统 Apple 本地识别。已下载模型跨 App 更新保留。模型就绪后可以离线使用。

## 签名与首次打开

本次发行使用 Developer ID 和安全时间戳签名。若 Release 的公证状态为“未公证”，macOS Gatekeeper 会阻止直接打开；签名通过不等于 Apple 公证通过。

1.0.1 候选尚未获得公证凭据，Gatekeeper 未通过。该状态不属于正式安全发行成功；保持当前已安装版本，待最终 Release 明确记录 Accepted、Staple 和 Gatekeeper 通过后再作为公开升级使用。

不要关闭 Gatekeeper，不需要删除 quarantine，不要执行所谓“修复已损坏”的终端命令。文件校验或签名不匹配时应重新从官方来源下载。

## 升级和回退

1.0 延续公开 0.18 和内部 0.20（533）的 `app.saytile.mac.mandarin-candidate` 身份、`~/Library/Application Support/Saytile Mandarin Candidate` 资料目录及相同 Keychain 服务。安装包里只有一个名为 Saytile 的 App。

升级不会主动删除原音、文字、修改稿、模型缓存或凭据。若需要回退，先退出新版，再恢复保留的旧 App；不要同时运行两个版本访问同一资料。回退前同时保留当前资料快照。不要用新旧 SQLite 文件互相覆盖正在运行的 App。

旧 RC1 身份 `app.saytile.mac` 使用独立的 `~/Library/Application Support/Saytile` 目录。本版不自动搬移 RC1 资料；原件继续保留。不能通过改文件夹名称合并两个数据库。

Sparkle 保留原有签名更新源，自动安装关闭；本次正式包若尚未进入已验证的更新源，以官网/GitHub 手动下载为准。

## 使用边界

临时文字会随音频证据修订；正式直接输入采用独立确认。不能确认目标所有权的网页会保留文字并拒绝写入；自行发送由用户决定。私人音频默认本地保存，iCloud 和云端服务未配置时不运行。

Mac 合盖时内置麦克风可用性不保证；本轮用公开人声文件验证原生识别流程，不把回放当作本人现场讲话验收。
