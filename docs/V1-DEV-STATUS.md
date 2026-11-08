# V1 开发状态 · no-api.9.1

当前设备修补候选来自[运行源码 `0a0cdeca`](https://github.com/haohongfei2001-png/saytile/commit/0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0)。[固定安装包](https://raw.githubusercontent.com/haohongfei2001-png/saytile/5ff88cb3ccf7c6ff4afb2f95360f5798d0be3632/deliverables/no-api.9.1/Saytile-1.0.0-rc.2-no-api.9.1-arm64.dmg) · [完整实机报告](../evidence/no-api9.1/README.md) · [逐项机器验收](../evidence/no-api9.1/snapshots/repeat-interrupted/machine.json)。

基线 no-api.9 的显式设备装配路径在同款计数探针中触发 AVFAudio 格式异常，直接中止进程。修补版明确选麦时按 UID 打开系统输入队列，继续使用原有音频日志和识别工作线程。设备移除会中断采集，必须明确选择可用设备才会恢复。

本阶段 13 项 PASS，4 项 FAIL，7 项 BLOCKED。正常 TextEdit 前台投递已实测；WKWebView 投递未确认，目标改变后没有重试或发送。受控睡眠后暂停标签仍旧是 P2。普通 Gatekeeper 执行拒绝；本包仅为 ad-hoc 工程候选。

三家真实云服务、真人准确率、相比最强单模型的收益与确认延迟均待凭据与授权。实际系统睡眠与第二支独立物理麦克风保留各自状态。标准公开分发需要发行方 Developer ID 签名和公证。

首轮驻留取得 22.32 小时、1,340 次真实采样和两对内核睡醒记录。观察中断，未取得退出原因。复测时间独立，状态见同一源码的逐项机器验收。

[原冻结版记录](https://github.com/haohongfei2001-png/saytile/blob/45256e38fb2d52d1c583965bb259d3c27edafc79/docs/V1-NO-API-DELIVERY.md) · [安装与数据回退](V1-INSTALL.md)。
