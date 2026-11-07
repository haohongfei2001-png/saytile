# Saytile RC2 · no-api.7

[DMG 与校验和](../../deliverables/no-api.7/) · [产品交付说明](../../docs/V1-NO-API-DELIVERY.md) · [运行源码](https://github.com/haohongfei2001-png/saytile/commit/4b97bd89b258fea29a0be61d4bd4c23cb5ab428c)

| 想核实的事情 | 可直接检查的原始证据 |
| --- | --- |
| 我拿到的是哪一个 App？ | [DMG、可执行文件、版本与源码](final/package-identity.json)；[安装升级](final/install-upgrade.json)、[卸载重装](final/uninstall-reinstall.json)使用同一二进制。 |
| 没有任何云密钥能否使用？ | [实际包内 Apple 本地识别、已保存 WAV、资料库终态](final/apple/signed-app.json)；[8 段合成语料的错误与延迟](final/apple/README.md)。 |
| 两个服务会否收到相同的声音？GPT 能改什么？ | [实际 Swift 网络客户端 ↔ localhost 服务端的逐项用例、日志及 CI](final/protocol/README.md)。两路各收到相同的 32,198 字节；迟到定稿与新讲话分别写回对应记录。GPT 只处理有来源的候选文字。 |
| 密钥与授权如何隔离？ | [实跑原生用例](final/protocol/native-network.log)包含真实 Security.framework 的独立随机服务名及虚拟值；[AppModel 检查](final/input/app-model.log)另行使用凭据替身，验证账户变化、撤权、预算和启用条件。两者均未使用用户 Key。 |
| 原生输入、复制会不会错投或发送？ | [真实 AppKit AX 与 WKWebView 边界](final/input/NATIVE-INPUT.md)、[9 个局部所有权场景](final/owned-range/README.md)。WK setter 虽应答但 DOM 未变，无投递声明或重放。 |
| 输入板是如何实际工作的？ | [安装包的真实面板、可操作控件与设计对照](final/ui/REVIEW.md)，含暂停、讲话结束回待命、选区复制、档案和连接向导。 |
| 声音与数据能否恢复？ | [本机音频、档案规模、迁移、进程恢复及完整逐帧比对](local/)；长跑终态以实际的 realtime-assessment.json 为准。 |
| 双专家比最强单模型准确多少？ | [四阶段质量和延迟记录](final/cloud-quality-boundary.json)。真实服务调用为零，各项指标未测量，不能从 localhost 或 Apple 合成样本推得。 |

[独立审查及限制](final/INDEPENDENT-REVIEW.md) · [原图来源核对](final/reference-source.json) · [仅在选择启用时所需的用户授权](../../docs/V1-USER-ACTIONS.md)。原有 RC1、个人资料和 main 不属于本次安装目标。
