# 0.21 发行候选技术边界

源头：PR49（产品整合）、PR50（可切换黑色品牌）、PR51（563及可靠性证据）。本轮工作提交6d75f0a增加空EOS分类及两轮发布器失败重放，主线从4caf73c选择性整合。完整选择清单在evidence/release-021/curation.json。

音频路径：CoreAudio/AVAudioEngine → 持续缓冲与独立PCMJournal → VAD分段 → 每段唯一ASR → LocalCandidateIngress/SingleTranscriptEngine → SQLite版本 → AppKit连续文字流。Qwen预览不授予稳定派发范围；EOS保留原模型定稿，不靠拼接旧词与新尾巴制造候选。两个未达标的新发布算法仅留在证据中，产品仍使用563算法。

存储：原音、识别候选、修订、用户编辑与草稿分别保存。删除原音不删除文字。迟到修订定位原录音；直接输入凭目标窗口、光标、文本范围及所有权确认增量执行，未确认投递不重放。新空EOS路径保留失败可重试及所有资料，不把“没有文字”当“无语音成功”。

界面：共享SaytileVoiceUI，Saytile自身AppModel提供状态；可编辑连续时间轴、自然段落复制、档案及设置保持用户已批准结构。紫色/黑色品牌往返不改变语音板控件或独立数据身份。

云端：独立授权，默认本地无需API。没有iCloud entitlement/profile时不能报告已备份。真实云同步/反馈验收没有账户能力时保持BLOCKED，首个本地Beta不因此自动HOLD；但本地响应性与发行安全失败仍为实际放行依据。

发行：同一Bundle ID和数据契约。构建号由packaging/BUILD_NUMBER提供，不再从分支提交数推导。DMG和App先签名并带时间戳；有授权才公证、装订并重新计算包哈希。只有实际Gatekeeper放行和产品验收通过后才准备官网/公开Sparkle切换，本分支不发布。

归档：旧研究/候选二进制/完整历史证据不机械搬入新主线，均通过原PR与固定提交追溯。当前main的官网源码原样保留。
