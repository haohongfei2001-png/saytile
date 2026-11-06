> 集成补充：以下是评估工作树基于 a9cffae 的原始核验快照，保留以便追溯。新的核心代码已支持 D 的 multilingualASR + 同一 GPT；`multilingualSingleExpertUsesSameCore` 已在 c31d84b 的完整原生 288 项回归中通过。真正仍阻断 A–E 的是 Saytile 专用凭据/服务配置及对应处理开关缺失；此处不据元数据断言用户没有给出任何费用授权，也不把历史技术缺口当作现有缺口。新候选身份和完整验收见工程 PR 的集成 receipt。

# 本轮本地核验报告

**A–E 云端评估 BLOCKED，性能 NOT_RUN；F NOT_AVAILABLE。没有云端准确率或速度结论。**

检查源码为 `a9cffae52d544b8a8939fce13d735b5ec1f2bc4f`。父流程最新 metadata-only 预检哈希为 `7a8bdfb8cb5d30e6b3aed5411725c0d08352855d829c7901700613f923f7bfa0`，实际值：配置不存在、云端关闭、启用服务为空、Keychain 匹配数 0、查询状态 -25300、未读取密钥值、未允许权限弹窗、付费请求 0、音频上传 false。没有沿用旧预检状态。

独立阻断包括：A–E 缺配置、缺 Keychain 凭据、云处理关闭、无本轮处理/费用授权；A/C/E 还缺已批准的 Qwen workspace。最终候选路径未提供，原生候选验证 NOT_RUN。检查时源码的单专家验证仅允许中文或英文角色，因此 D 的 `multilingualASR + GPT6` 另列待修复阻断；准备文件已保持正确角色与单专家参数，待父工程新候选验证，不变更 UUID 或绕过 consent/Keychain。

| 已核验事实 | 数量与结果 |
|---|---|
| 冻结 manifest | 134 项，hash 未变 |
| 磁盘现有 WAV | 112 个；全部原始样本的文件 SHA-256、PCM16/16 kHz/mono、帧数与 payload 字节数通过 |
| 冻结本轮面板 | 24/24 可用，中/英/混说各 8；参考与音频 hash 复用 |
| 本地缺失清单项 | 22 个派生/控制样本；不在本轮 24 中，不生成补充语料 |
| Apple 固定中文历史记录 | 112，文件收据、ID、音频 hash 与 engine 校验通过 |
| Apple oracle locale 历史记录 | 112，同上；使用已知参考语言，不能算自动混说结果 |
| 本地 Qwen MLX 历史记录 | 112，同上；不能冒充 Qwen Message 云结果 |
| 历史合计 | 336；A–E 云记录贡献 0 |
| 新准备命令 | 120 个未执行 argv；5 份禁用云处理的配置，每份恰好同一个 GPT 核心 |

机器收据见 `preflight.json`、`preflight-audio-integrity.json`，当前未测评分见 `not-run-summary.json`。所有数字来自本轮实际检查；没有复用历史 oracle locale 分数、合成 gold 输出或未执行测试计数。

新增 20 项 Python 测试通过，复用评分模块的 43 项测试通过，总计 63 项。测试覆盖配置形状、ID/hash 不变、禁止自动授权、null 与零分区分、合成/gold 与正式面板隔离、trace 索引生成和篡改拒绝、代次与配对身份、失败和缺失阶段、原始 ASR 与 GPT 选择分离、同 MER 下同时发生修复和新增错误。测试中的模拟 trace 仅驻留隔离临时目录，不纳入云结果。

下一步由父工程在原生候选完成后接入：使用 README 中参数化命令；确认 D 校验支持，保留唯一 GPT、完整 PCM 平等分发与原生授权校验。当前无需用户测试或补做操作。本提交只交付本地准备和评分能力，真实 A–E 请求仍未执行。未推送、未合并，未改动原生引擎、原测试目录、既有 benchmark 或全局文档。
