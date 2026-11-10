# Saytile 中文本地识别工程候选

版本 `1.0.0-rc.2-local-asr.6`，原生产品源码 `a55d51a1ff4711340bc63ea5c8ecd927dd2327d3`，适用于 Apple Silicon、macOS 26 及以上。本目录的 DMG 为 61,646,743 字节。包内包含原生助手、Metal 库与开源声明，第三方权重按需下载。本地识别不需要 API 密钥。

在普通 Mac 上应先核对 SHA256SUMS.txt 与 Gatekeeper。当前 Developer ID 签名、时间戳和 Hardened Runtime 已验证，Gatekeeper 返回 `Unnotarized Developer ID`。公开分发仍等待 Apple 公证。工程验收使用从只读 DMG 安装的隔离副本。原生安装和旧库迁移收据在 [delivery/install](../../evidence/mandarin/delivery/install)。

DMG 使用正式的 `app.saytile.mac` 身份。保留已有版本和数据备份后才能进行正式升级。候选已在隔离数据上验证 v5 → v6，复查了 WAV 哈希、版本、编辑稿、授权范围和测试 Keychain 项。需要回退时退出候选，恢复升级前的应用及与其匹配的数据备份。v5 应用会拒绝打开 v6 数据库。

设置中选“本机识别”即可使用 Apple 已安装的中文资源，或在设置中准备系统资源。手动选择可下载 Streaming Paraformer 或 Qwen 0.6B。第三方模型完成 SHA-256 校验后启用，切换影响下一段录音。外部文字派发沿用目标和 UTF-16 范围保护。本地识别可离线运行。可选 GPT 核对需单独授权。Zipformer 的普通下载入口等待权重商用许可及产品验收。

[验收报告](../../docs/V1-MANDARIN-LOCAL-ASR.md) · [SHA-256](SHA256SUMS.txt)

独立 macOS CI 已从空目录完成三个第三方模型的下载、暂停续传、校验、复用和删除。本机现有代理出现过第三方模型从空目录下载超时。短后缀续传、完整哈希和已准备模型的离线使用通过。详情见上述验收报告。
