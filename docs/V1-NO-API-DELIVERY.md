# Saytile V1 无 API 工程交付状态

当前工作从 PR #6 最新分支 `engine/single-transcript-integrated-20261107` 派生，独立开发分支为 `codex/single-asr-gpt6-closeout-20261107`。生产 `main`、RC1 与已发布 no-api.9.1 包未修改。原工作区未跟踪文件保持原样。

## 当前架构

One ASR Expert + One GPT-6 AI Core + SingleTranscriptEngine。每个录音只选一个 ASR：Auto/中文/English/中英混说由 LanguageProfile/Registry 决定；Qwen、AssemblyAI、Soniox 是待对照的初始候选。Apple SpeechAnalyzer 用于本地与网络故障接替。GPT-6 Astra 只处理候选文字，不能听原音。当前无 API Key，所有真实云连接、转写和质量指标均 NOT_RUN。

## 本轮已修改（尚未形成发布候选）

- 持久 GPT review 错误进入现有 failover reporter；EOS review 遵守阻断/退避，429 minimumRetryDelay 不再被绕过。
- 英文基数/序数/小数及金额比较签名加入保护；原始 ASR span 不被改写。
- 回放元数据记录实际 framesSubmitted、inputEOF、inputEOFAt；评分器不再要求最后一个词的 audioEndSeconds 等于 WAV 全长，并验证 provider run/session 完成。
- 评测计划改为冻结 24 条的 A Qwen+GPT、B AssemblyAI+GPT、C Soniox+GPT，共 72 次，未授权时 NOT_RUN。
- 设置增加 Auto/中文/English/中英混说；生产会话仅为所选语言启动一个云 ASR。

## 本机验证与阻断

- benchmark Python harness：24 项测试全部通过（包含完整 10 秒音频、8 秒语音 + 2 秒尾静音、0.5 秒尾静音与毫秒舍入，以及少发 PCM、缺 EOF、run 未完成、EOF 时序异常）。
- `swift build`：通过（SaytileKit 与 Saytile-product 均成功链接）；存在 Command Line Tools framework search-path warning 和既有 AppModel capture warning，不影响本次构建结果。
- `swift test`：BLOCKED。连接 Mac 只有 `/Library/Developer/CommandLineTools`，没有完整 Xcode/TestingMacros plugin；编译测试 target 时找不到 `TestingMacros.TestDeclarationMacro`，因此不是测试断言失败，也不能计为测试通过。完整 XCTest/Swift Testing 以 GitHub macOS CI 为准。
- 历史 foreground probe `-5` 的旧运行未留下崩溃报告，不能追认具体根因；后续 no-api9.1 实机收据已通过独立 NSTextView/AppKit 目标，WKWebView 仍为 unverified。当前已增加阶段日志、SIGTRAP 信号名和 crash report 自动保全，后续失败可定位。不得把 WebKit unverified 记为通过。
- Developer ID、公证、staple、Gatekeeper 隔离首次安装未完成；发行 BLOCKED。

## 构建与发行脚本

- 修复 `build-app.sh` 与 `package-beta.sh` 的互相调用循环：前者只构建 App，后者调用前者后生成 DMG。
- `package-beta.sh` 支持独立 `SAYTILE_DMG_OUTPUT`，拒绝覆盖已存在候选，并为每个 DMG 写独立 SHA-256 sidecar。
- ad-hoc 签名只用于工程候选；Gatekeeper、公证和 staple 仍 BLOCKED。

## 真实云端待验证

真实 Qwen/AssemblyAI/Soniox 鉴权、Workspace/区域、WebSocket 事件、EOS/final drain、GPT Responses WebSocket/HTTP fallback、429/超时恢复、usage/cost、24 条 A/B/C 准确率/关键错误/延迟均需真实凭据及单独费用与数据处理授权。不得使用私人录音，不得编造结果。

最终状态分别记录：NO_API_ENGINEERING_READY（需 CI/完整原生测试确认）、LIVE_CONNECTION_PENDING、LIVE_PROTOCOL_VERIFIED、LIVE_TRANSCRIPTION_VERIFIED、QUALITY_VERIFIED、PRODUCTION_READY。当前不宣称后五项通过。
