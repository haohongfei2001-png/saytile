# 首次连接验收矩阵

冻结源码为 `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`。工程上已有**填好三项服务、授权一次检查、成功后自动启用**的完整路径。真实供应商调用为零。在这台 Mac 上填入有效账户后，首次云端转写能否完成，仍待授权实测。[云端边界](cloud-quality-boundary.json)

| 操作 | 产品行为 | 已有验证层 |
| --- | --- | --- |
| 填写账户 | 默认使用 Qwen 中文、AssemblyAI 英文和 GPT-6 Astra 文字融合。Qwen 还需与 Key 匹配的地域和 Workspace ID。三项服务分别授权处理语音或候选。设置区显示已保存、已准备和已连接。 | 真实原生窗口操作了 Workspace、3 个 SecureField、保存和授权控件。这次 UI 使用注入的凭据存储。[原生操作日志](ui/run.log) |
| 保存、替换或移除 Key | 按服务与配置身份访问 Keychain。设置页查状态只请求元数据，运行服务时才读取所选凭据。空值不能覆盖已有 Key。 | 独立随机服务名下的**真实 Security.framework Keychain**完成虚构值的新增、读取、替换、删除和命名空间隔离。UI 验证与真实 Keychain 检查分别执行。未读生产 Key。[存储实现](../../../Sources/SaytileKit/CloudCredentials.swift) · [专项测试](../../../tests/SaytileKitTests/CloudCredentialTests.swift) · [原始日志](protocol/native-network.log) |
| 授权检查及费用 | 三项配置、Key 与服务授权齐备后，勾选本次费用/上传同意，再点「授权并连接」。检查使用内置约 6.3 秒合成 PCM，清空话题和术语，在隔离存储运行。最多 2 路语音连接、6 个 AI 请求，每请求至多 4096 输出 token，联网时限 90 秒。界面说明实际账单可能另外包含输入和语音费用。 | 原生控件实际展开费用说明并提交。无授权、缺 Key、取消和并发预算有 AppModel/Swift 检查。localhost 验证了真实请求体和 WS/HTTP 回退共用额度。[原生设置](../../../Sources/SaytileApp/RecognitionSettingsView.swift) · [检查实现](../../../Sources/SaytileKit/CloudConnectionVerification.swift) · [本地协议记录](protocol/wire-audit.json) |
| 检查三服务 | 同一音频并行发给两位专家，GPT 使用候选。服务终态、专家最终候选、非空文字和整条管道完成后才可通过。仅握手或收到初稿不足以启用。 | 生产 URLSession 与真实 localhost WS/HTTP 对端交换 PCM、候选和 EOS。普通、WS 不支持和 churn 各用 2 次 GPT 请求，逐次断开再连用 4 次。模拟结果停在 `NO_API_ENGINEERING_READY`，不能给真实账户开云端。[协议证据](protocol/README.md) |
| 成功、启用及重启 | 只有 `live` 报告达到 `LIVE_TRANSCRIPTION_VERIFIED` 且匹配当前配置，才持久化成功收据并自动应用。启动时，配置已开云端却无匹配收据会回本机。 | AppModel 和原生 UI 通过 **TEST_ONLY 注入的成功报告**走过自动启用分支。尚未观察到真实供应商成功收据。[AppModel 收据](input/app-model.log) · [启用和启动代码](../../../Sources/SaytileApp/AppModel.swift) |
| 换 Key、Workspace 或撤销授权 | 改地域、Workspace、模型、凭据代次或服务授权使连接指纹失效。修改 Key 前同步停云端，成功才轮换不含 Key 内容的 UUID。修改失败仍留本机。旧录音的上传范围绑定目的地与凭据代次。单独修改全局启用开关属于设置草稿，点「保存并应用」后生效。 | 指纹变更、进行中的旧读取、迟到结果、重启和旧原音范围有专项测试。Workspace 或 Key 变更不能沿用旧收据。未测试真实账号更换或远端吊销传播时间。[指纹检查](../../../tests/SaytileKitTests/CloudConnectionVerificationTests.swift) · [读取撤权](../../../tests/SaytileKitTests/CredentialReadRevocationTests.swift) · [旧原音范围](../../../tests/SaytileKitTests/SavedAudioAuthorizationTests.swift) |
| 取消与失败 | 停止本次检查，保留每路已完成或失败状态。下一次检查等待旧任务清理，迟到成功不能重新启用。供应商已处理的请求仍可能计费。 | 原生 AX 实际操作取消，验证后端为注入实现。受控生命周期测试的两路服务均停止。真实 localhost GPT socket 取消被对端观察到。实际云端账单和取消延迟未知。[原生取消日志](ui/run.log) · [AppModel 取消日志](input/app-model.log) · [连接生命周期日志](protocol/native-network.log) |

此审查沿用该 SHA 的既有源码和检查记录，未发现这些记录可复现的新连接故障。剩余验收是经授权的一次真实三服务检查，保留服务状态、合成音频文字、调用数和耗时。无需用户录音或提供私人草稿。
