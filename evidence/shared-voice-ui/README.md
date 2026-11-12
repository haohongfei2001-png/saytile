# 两个宿主的语音板原生验收

独立 Saytile 的产品源码为 `85dbd399`，Nearpane 为 `f9671d15`。Nearpane 的依赖清单锁定 Saytile 的 `2c9c95e8` 及五个共享源文件的 SHA-256。两端使用同一套 SwiftUI 材质、两枚控件、语音状态图形与可选择的 TextKit 文字流。音频、识别、档案、权限和生命周期分别由各自宿主管理。[Nearpane Draft PR #7](https://github.com/haohongfei2001-png/nearpane/pull/7)

| 本机检查 | 结果 |
|---|---|
| 原生窗口取证 | PASS。1920 × 1080 pt 主屏，玻璃为 240 × 243 pt，右侧和顶端对齐。三态的窗框及 AX 正文、复制和语音按钮坐标分别一致。两个宿主上均能实读苹方 19.5 pt。 |
| 材质与三态 | PASS。根据首次对照修复了 Nearpane 在语音玻璃背后重复叠加的侧栏材质。修复后三态逐颜色通道的平均绝对差均低于 0.88/255。 |
| 复制与文字 | PASS。两个真实宿主都有一份可选择的连续文字流。在专用剪贴板上通过整组与选区快照测试。Nearpane 另覆盖连续语音跨页、之后的新组与编辑稿。 |
| 窗口与重启 | PASS。Saytile 实际拖动、双向缩放、隐藏重开、跨两块显示器及重启恢复后再复位。Nearpane 独立资料目录两次正常冷启动及退出。 |
| 不可替代的现场测试 | 本轮没有采集现场麦克风或进行付费云端调用。状态和文字由隔离夹具提供。物理拔插显示器未执行，已用几何回归覆盖断连与重新连接。 |
| 候选边界 | 本地签名工程候选。Nearpane 的语音体验身份使用独立资料、关闭真实桌面读取和第三方窗口整理，避免在体验期间改变当前桌面。正式宿主保留原有 Spaces 及窗口管理能力。 |

三态对照中，左为 Saytile，右为裁下的 Nearpane 语音区。[暂停](native/panel-paused-pair.png) · [待命](native/panel-standby-pair.png) · [识别中](native/panel-speaking-pair.png) · [Nearpane 原生整窗](native/Nearpane/panel-speaking-window.png)

精确几何、AX 字体和交互、逐像素比较以及失败后修复记录见[窗口收据](native/comparison.json)。本机套件和包来源见[机器记录](acceptance.json)、[双屏手势](two-display-gestures.log)及[重启记录](nearpane-relaunch.log)。
