# Saytile V1 RC2 · no-api.9 验证证据

[固定运行源码 dc26fe3c](https://github.com/haohongfei2001-png/saytile/commit/dc26fe3c59ba55994d29e99ada8d2f0b49ad9886) · [DMG 与校验和](../../deliverables/no-api.9/) · [完整交付状态](../../docs/V1-NO-API-DELIVERY.md)。文档与证据可以有更新的提交，安装包始终对应这里的运行源码。main 与已安装的 RC1 不属于测试目标。

本候选的最终证据已收齐：按真实时钟采集 1,800.41 秒；60 段、179 个 WAV 的 28,800,000 帧与独立参考逐字节相同，ring 丢帧 0，上传授权 0。[最终清单](final/delivery-manifest.json) · [逐帧比对](local/realtime-assessment.json) · [固定下载回读](final/public-download.json)。

| 可回答的问题 | 证据及其界限 |
| --- | --- |
| 这是不是正式原图？ | [GitHub 原始 JPEG](../../design/approved/Saytile-original-visual-reference-20261107.jpeg)、[来源与指纹](final/reference-source.json)。1536 × 1024，SHA-256 `58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5`。 |
| 实际面板是否按原稿工作？ | [实际包内窗口、控件、选区和几何](final/ui/REVIEW.md)、[同尺度对照](final/ui/original-comparison.json)。卡片 344 × 234 pt；颜色由后方环境透出。另有[受控背景传色对照](compositor/)：WindowServer 只合成两个自有窗口；没有截取桌面，不能推出任意壁纸上的视觉效果或用户主观认可。 |
| 无 Key 是否真的识别过？ | [签名 App 的本机文件输入、原音与最终文字](final/apple/signed-app.json)；[八条合成中文的参考、实际输出与错误](final/apple/README.md)。另有[单个真实采集进程的连续语音测试](final/local-vad-apple/README.md)：真实 VAD 分段、Apple 增量文字与 PCMJournal 持久保存一起执行。输入均为合成语音，不是现场讲话或真实云服务。 |
| 首次连接要不要写代码？ | [设置向导与证据层级](final/connection-contract.md)。三项凭据、Qwen 地域与 Workspace、逐服务及本次检查授权齐备后，真实检查全通过才持久启用。 |
| 双路 ASR 与 GPT 实际执行到哪一层？ | [正式网络客户端与本机 WebSocket/HTTP 服务端](final/protocol/README.md)：两路接到相同 PCM，走真实解析与融合代码，但服务端受控，不能证明供应商账户可用或质量改善。 |
| 外部输入是否修改别人的文字？ | [隔离原生 AX、UTF-16 范围所有权与 WKWebView](final/input/NATIVE-INPUT.md)。未确认写入不自动重放；不发送。未访问真实文档或任意前台网页。 |
| 版本升级会否破坏原有数据？ | [实际 RC1 升级、备份与回退](final/install-upgrade.json)、[卸载重装](final/uninstall-reinstall.json)、[本机备份、强杀与存储测试](local/)。所有可写资料库均为独立测试库。 |
| 能否向普通 Mac 分发？ | [签名与 Gatekeeper 实测](final/gatekeeper.json)：严格校验通过，普通执行策略拒绝。没有调整系统策略。公开分发仍需产品的 Developer ID 签名、公证。 |
| 双专家比最强单模型改善多少？ | [逐阶段未测字段](final/cloud-quality-boundary.json)。真实供应商调用为零；准确率差、获益条件和额外确认延迟均未知。 |

[独立审查](final/INDEPENDENT-REVIEW.md) · [今后选择连接所需的授权](../../docs/V1-USER-ACTIONS.md) · [固定色彩的前一版工程基准](../no-api8/README.md)。
