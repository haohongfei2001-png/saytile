# SingleTranscriptEngine 实施状态与契约

更新：2026-11-07。当前实现目标为单 ASR + GPT-6；此前双 ASR fanout 不再作为生产路径。

## 当前代码切片

1. `LanguagePreference`、`LanguageProfile`、`ASRModelRegistry` 提供 Auto/中文/English/中英混说选择。Auto 使用近期语言标签记录与 macOS locale；未知语言不强行启动云 ASR。
2. `RecognitionConfiguration.activeModels` 只暴露选中的一项 streaming ASR 与唯一 GPT-6。`MultiRecognitionSession` 创建 fanout 时只建立该 ASR 通道，并将选定配置固定在当前 generation。
3. `SingleTranscriptEngine` 继续作为唯一发布者。GPT review 仅使用 ASR 候选来源 span；没有证据的词不得发布。
4. Apple 本地识别仍独立于云端路径，在无云选择/云故障时使用原音恢复，不作为并行云专家。
5. 持久 GPT review 失败进入统一 failover；authorization/permission/quota 阻断配置，connection/429 退避；EOS 不绕过 60 秒限流保护。
6. `RecognitionFusion.protectedSignature` 补充英文基数/序数/小数及金额表达的比较归一化，不改原始 span/文字。
7. benchmark 完整性使用发送帧数、input EOF、EOF 时间、session 终止时间和 provider run completed；词尾时间仅作声学对齐。

## 验收边界

- 本轮 Python harness：24 条冻结 panel、A/B/C 三配置、72 次流程准备；无凭据时 NOT_RUN。
- 离线 harness 回归覆盖尾部静音、PCM 少发、缺 EOF、run 未完成和时序异常。
- 真实供应商连接、语言质量排名、GPT 新增错误、真实费用和端到端延迟必须等待用户提供 Key、模型权限与单独授权。
- `swift build`：当前连接 Mac 上 SaytileKit 与 Saytile-product 构建通过。`swift test`：BLOCKED，设备只有 Command Line Tools，缺少完整 Xcode/TestingMacros plugin；不得将构建通过当作测试通过。
- 前台 probe -5、真实 ChatGPT/Codex 输入、Developer ID/公证仍单独验收。
