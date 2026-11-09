# no-api.10 机器证据

[逐项状态和额外试验](machine.json) · [交付报告](../../../docs/V1-NO-API-DELIVERY.md) · [签名镜像及校验值](../../../deliverables/no-api.10/)

产品源码为 `5639058e6b178027861b18cc0521387487c919d5`。安装包提交为 `319041e6d942122b0a42bfa54fcef5a1eb045942`。镜像和所含二进制的散列、系统签名、下载回读分别见 [identity](app/identity.json)、[signing](app/signing.json) 和 [remote-download](app/remote-download.json)。完整编译及制包使用相同源码，Developer ID 签名阶段对 App 和 DMG 分别校验。首次公开分发仍待 Apple 公证。

| 证据 | 采集范围 |
| --- | --- |
| [tests](tests/) | 完整 Xcode，无过滤 Swift Testing、AppModel 和 HTTP/WS 模拟服务的网络记录。 |
| [input](input/) | 独占 WindowServer。真实 WKWebView、NSTextView、TextEdit。附加冷启动拒绝和改进测试启动时序的独立复查分别保留各自 SHA。两次已对照产品源码完全一致。 |
| [ui](ui/) | 独立 Mac 直接运行签名包的原生控件。由测试后端返回的连接状态仅用于控件验收。 |
| [hardware](hardware/) | 物理输入端点、计帧和路由移除，未读取或保存麦克风内容。 |
| [lifecycle](lifecycle/) | 系统路由断开和恢复、带有效采集的睡眠通知、内核睡眠尝试及权限现状。 |
| [store](store/) 与 [app](app/) | 独立数据库异常恢复，RC1 与 no-api.9.1 的升级、回退、下载镜像安装与 Gatekeeper。 |
| [speech](speech/) | 两小时真实时间采集，两句合成语音反复进入 VAD、Apple 本机识别、原音及数据库。 |
| [continuous](continuous/) | 现有 AudioRealtimeProbe 连续运行 1,800 秒。关闭 ASR，核对 179 个 WAV 文件及数据库帧数。 |
| [signed-idle](signed-idle/) 与 [separate-footprint](separate-footprint/) | 90 分钟同一签名 App 的 RSS/CPU 原始序列。物理内存和能耗计数另测 10 分钟；90 分钟附属计数文件丢失。 |

[完整 Xcode 与前台](https://github.com/haohongfei2001-png/saytile/actions/runs/42613660881) · [签名包独立验收](https://github.com/haohongfei2001-png/saytile/actions/runs/42615594346) · [虚拟机断网及采集](https://github.com/haohongfei2001-png/saytile/actions/runs/42616492743) · [冷启动复查](https://github.com/haohongfei2001-png/saytile/actions/runs/42618075854)
