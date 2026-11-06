# Saytile V1/V2/V3 开发路线

日期：2026-11-07。基于当前 PR #4 工程候选，不代表以下能力已经实现。

## 总体顺序

先修正架构边界与产品路径，再做小规模同音频验证，再按证据增加模型。不要继续一次性增加更多 provider。V1 以常驻表达工作台完整交付为终点。

## 阶段 0：架构收敛与现状核实（P0）

| 项目 | 计划 |
|---|---|
| 目标 | 让 Apple 本地路径与云端候选统一进入一个录音/候选/版本协议；明确当前 PR #4 哪些模块真实接入、哪些只是兼容入口 |
| 当前状态 | PR #4 已实现云端 MultiRecognitionSession 和 Apple SpeechAnalyzer 旧路径；官方 PR 描述确认两路径此前互斥 |
| 技术方案 | Capture/PCMJournal 不动；新增 LocalRecognitionAdapter 与统一 Candidate ingress；Policy Engine 选择本地/云端计划；禁止两套 session 分别写 transcript |
| 依赖 | Swift Concurrency、SpeechAnalyzer、现有 SQLite schema 3 |
| 改造 | AudioController、CaptureWorker、MultiRecognitionCoordinator、RecognitionAudioFanout、Store、RecognitionConfiguration |
| 验证 | schema migration/reopen；Apple 与 cloud synthetic 同一录音候选；断网/恢复；撤销授权 |
| 验收 | 同一个 recordingID/audioEpoch/generation 下，Apple 与云候选均进入 Candidate Store；Capture 在 provider 挂起时持续写盘 |
| 风险 | 现有 Apple 路径重构会破坏 V1 RC1 兼容；必须分支演进并保留旧入口 |

## 阶段 1：真实多语言主路和模型边际收益（P0）

| 项目 | 计划 |
|---|---|
| 目标 | 证明哪条模型路径最适合中英混说实时输入 |
| 当前状态 | Qwen Message/AssemblyAI/Meta/Soniox 适配器已实现；真实云测未执行 |
| 技术方案 | 以 Soniox STT v6 做多语言混说候选；对现有 112 条语料选 24 条代表性样本，配对比较 Apple、Soniox v6、Qwen+Assembly、Meta challenger；不得新增大规模下载 |
| 依赖 | 已存在音频与参考文本、Soniox v6 key/权限、用户授权的音频处理预算 |
| 改造 | vendor config/version；token language spans；统一指标脚本 |
| 验证 | CER/WER/MER、关键实体/数字/否定错误、首显/稳定/完成 p50/p95、音频上传失败率、费用 |
| 验收 | 至少 24 条全覆盖；每个方案同录音配对；报告按中文/英文/混说分层；不以总体平均掩盖某语言退化 |
| 风险 | Soniox v6 刚更新，v5 指标不可移植；模型服务可能限流/地区差异 |

## 阶段 2：自适应调度与证据融合（P0）

| 项目 | 计划 |
|---|---|
| 目标 | 让额外模型只在真实增益场景参与 |
| 当前状态 | 候选隔离、AI 仲裁、音频复听已实现；语言级路由和声学 LID 未完成 |
| 技术方案 | 先确定性共识；只对不一致、关键语义、术语/OOV、语言标签不稳的时间范围调用 challenger；仅对未解决冲突调用文本 LLM；仅当文本候选不足以判断时调用音频复听 |
| 依赖 | 源 sample clock、provider token timing、Soniox language label、现有 Gemini audio adapter |
| 改造 | RecognitionPolicyEngine、Alignment、FusionCoordinator、audio review clipper |
| 验证 | 消融：主路；主路+第二专家；+文本裁决；+音频复听；比较错误修复数与新引入错误 |
| 验收 | 任何新增模型默认启用必须证明关键错误净下降且 p95 延迟/资源代价可接受；没有增益则保留为手动 challenger |
| 风险 | 模型错误相关；语言标签修订；截取片段丢失上下文 |

## 阶段 3：V1 表达工作台闭环（P0）

| 项目 | 计划 |
|---|---|
| 目标 | 从常驻录音到历史复用和安全插入完成完整产品体验 |
| 当前状态 | 采集、存储、历史、编辑、输入 ledger 已有工程基础；产品级长时 soak 和 UI 首显验收未完成 |
| 技术方案 | 自由记录与直接输入分开；raw/formatted/user draft 分层；Backtrack 仅限未派发区间；插入由现有 ledger 管理 |
| 依赖 | AppKit/SwiftUI、Accessibility、SQLite |
| 改造 | AppModel、输入板、档案、搜索、设置与权限 onboarding |
| 验证 | 24h soak、网络断连、设备切换、休眠唤醒、权限撤销、目标变化、重复输入检查 |
| 验收 | 不要求逐句启动；关面板不停止；任一识别失败不停止采集；用户稿不被覆盖；不自动发送/回车 |
| 风险 | “始终待命”误解为全天监听；必须有明显状态和快速暂停 |

## 阶段 4：本地模型和功耗准入（P1）

| 项目 | 计划 |
|---|---|
| 目标 | 在 M5 24GB 上找到真实可用的离线质量路径 |
| 当前状态 | Apple SpeechAnalyzer 可用；本地 Qwen3/WhisperKit/Parakeet 未在目标机完整实测 |
| 技术方案 | 先 Apple；再比较 Qwen3-ASR 0.6B、WhisperKit、Parakeet；仅一个本地主路，避免同时常驻多个大模型 |
| 依赖 | Apple Silicon runtime、模型权重/许可证、Metal/CoreML/MLX 或可行推理后端 |
| 改造 | LocalModelRegistry、download manager、resource monitor |
| 验证 | RTF、首字延迟、RSS、CPU/GPU、温度、电池、60min 连续稳定性 |
| 验收 | 满足 FINAL-ARCHITECTURE 的门槛；未达到则 Apple 本地保底 + 原音待识别，不宣称离线同质量 |
| 风险 | Qwen 官方 streaming 后端与 macOS 本地推理栈不一致；模型内存/热负载 |

## 阶段 5：上下文与可撤销格式化（P1）

| 项目 | 计划 |
|---|---|
| 目标 | 提升技术词、专有名词与成稿自然度 |
| 当前状态 | 有用户话题/术语 prompt；无完整上下文引擎 |
| 技术方案 | V1 先支持 app identity、用户选区、用户词典和本次 session hints；原文 ASR 与 formatting 分离；保留 Undo |
| 依赖 | macOS NSWorkspace、AX selected text（按需授权）、provider context APIs |
| 改造 | ContextSnapshot、TermDictionary、FormattingPipeline |
| 验证 | 无上下文/有术语/选区上下文同音频对照；隐私字段测试 |
| 验收 | 上下文不阻塞首显；禁用后零读取；每次发送的上下文可审计；格式化可撤销 |
| 风险 | AX 权限与自定义控件兼容；上下文可能错误 bias ASR |

## 阶段 6：V1 发布验收（P0）

| 项目 | 计划 |
|---|---|
| 目标 | 将工程候选变为可放心使用的 V1 |
| 当前状态 | PR #4 未合并；生产 RC1 仍独立 |
| 技术方案 | 完整测试、隐私审查、签名/公证、升级/恢复、文档和 onboarding |
| 验证 | CI + 真实 Mac 自动化 + 24h soak + 断网 + 云服务对照 + 删除恢复 |
| 验收 | 不存在数据丢失 P0；音频可恢复；用户稿安全；稳定输入无重复；安装更新闭环 |
| 风险 | 未授权云测试不能作为 release gate 的缺失项；但云质量承诺必须标注边界 |

## V2：轻声与共享办公

仅在 V1 稳定后进行。重点是近讲麦克风、低音量讲话、降噪、回声消除、噪声鲁棒性和耳语识别。以用户场景采样验证，不将通用降噪等同于 whisper recognition。禁止为了 V2 提前把 V1 做成会议录音工具。

## V3：个人化语音输入系统

加入可查看/编辑/撤销的个人词典、经确认纠错的长期学习、个人表达偏好、系统级输入法，以及经用户授权与 PAIA/备忘录/文档的协同。任何学习必须来源于用户确认，提供删除和关闭机制。

## 当前不做

多人会议/声纹归属、Agent 工作流、自动发送、持续屏幕采集、云同步、通用 prompt 市场、任意工作流 DSL、同时常驻多个本地大模型。
