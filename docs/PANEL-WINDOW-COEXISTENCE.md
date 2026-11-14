# 0.14 · 浮板与实体边界

基于 0.13（476）源码 `0fbca1d892bbc8aa550c4439b8cfcb045af825ae`。本轮只涉及窗口共存、原玻璃材质的全屏响应、设置和必要回归；ASR、用户资料及 Nearpane 未修改。

设置 → 输入与快捷键 → 输入板 → 显示方式：

- **浮板（默认）**：保持现有覆盖行为，不调整其他应用窗口。
- **实体边界**：获得系统辅助功能权限后，为实际可见的语音板留出空间。普通窗口优先保持尺寸平移，空间不足才缩小；不会把全屏目标缩小。收起板、退出 Saytile 或切回浮板时，只恢复仍属于 Saytile 自动调整的窗口。用户自己调整过的窗口不被旧位置覆盖。
- **全屏**：两种模式都提高原白色毛玻璃的遮挡；基于已确认的附近原生控件几何作有界位移，不读取文字或截取屏幕。控件无法被安全确认或没有邻近空位时，保持位置。编辑、拖动或按住鼠标时不自动移动板。退出全屏恢复用户选择的位置，不把临时避让保存为偏好。

这通过公开 Accessibility API 实现，不宣称能设置 macOS 的全局保留区域。应用自身最小尺寸、只读窗口、隐藏 Spaces、系统弹出层或不公开控件的应用可能无法调整/避让；设置中如实显示限制。没有权限仍可录音、编辑和复制，不自动弹授权框。

## 可复现验证

- `scripts/test-panel-boundary.sh`：真实自有 AppKit 窗口、公开 AX、严格 PID 白名单；不会写用户窗口。实际系统全屏需 `SAYTILE_PANEL_NATIVE_FULLSCREEN=1`，测试目标自主进入/退出，回到原活动应用。
- `scripts/test-adaptive-panel.py --source <SHA> --glass-only --output <dir> --expect-pass`：同文字/同背景/同尺寸的4种原生玻璃状态。材质环境注入与真正系统全屏分开记账。
- `tests/SaytileKitTests/PanelCoexistenceGeometryTests.swift`：尺寸保持优先、最小尺寸、负坐标、无解、最短位移、滞回及异常几何。
- `scripts/test-app-model.sh`：模式偏好持久化，瞬态全屏状态不持久化；原文字编辑、按钮/缩放和资料回归。

最终安装与真实测试状态以本轮机器收据为准。物理麦克风按用户要求 NOT_RUN；不把测试窗口或公开音频替代现场讲话。

## 公开接口依据

[Apple AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue) 定义位置/尺寸写入与拒绝结果；每次写入前验证窗口身份与原几何，并读取确认。
[Apple activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification) 通过 NSWorkspace 通知中心感知 Space 切换；以实际 AXFullscreen 为优先依据。
