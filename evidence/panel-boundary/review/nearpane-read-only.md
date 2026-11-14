# Nearpane → Saytile 窗口共存复用审查（2026-11-14）

审查对象 `/Users/hhf/Documents/GitHub/nearpane`，本地 `implementation/host-foundation-20261109` / `f10ccf1ec8542f83dbe7ae04871864bb04f5cdef`。只读源代码和 GitHub 元数据；未安装、启动、移动应用/窗口，未读标题、文稿或私人内容。机器文件哈希见同名 JSON。

## 当前状态

- 远端同分支 `d262e60b27f7c2db70821371b0606c6edeb70486`，本地领先 12 commit；main `e3f26bbaa1ba4da87da56b475f5fa6fa5daa8766`。
- 活跃 WIP 现为 3 个修改的 acceptance 脚本和 3 个未跟踪 P5.9 验收文档。审查期间 WIP 增加，证明有其他任务正在进行；未读取或覆盖其改动内容。
- Draft PR #9 (`bcfeb9544c15f3f6183e59b4bd819597699c68f8`) 基于 #8 glass-rail，#8 基于独立视觉成果；#7 shared-surface 也独立保留。#9 的 native CI 成功，Vercel 状态失败，不能称全部检查通过。#9 修改共享语音视图/依赖，不包含这里审查的 AX 占位管理实现。
- 根/上层/仓库内没有额外 AGENTS.md。README 和 ADR 明确区分产品目标与已验证实现。

## 结论

**Nearpane 没有让 macOS 为第三方 App 原生注册工作区保留边界的实现。** `Sources/NearpaneCore/DesktopWorkArea.swift:13–33` 只是计算较窄的 WorkRect，再由授权 AX 管理窗口。ADR-013:15 自己明确 NSScreen.visibleFrame 不会因为面板出现而改变。当前 SDK 的 visibleFrame 是只读值；检索到的公开 AppKit/AX 接口没有第三方全局保留区域注册接口。不能承诺任意应用、任意时刻都绝不越界。

**全屏控件避让有纯几何算法，但并没有接上第三方控件发现。** `Sources/NearpaneCore/FullscreenTransition.swift:161–188` 可从已确认的障碍矩形找距用户 anchor 最近的安全位置；`Sources/NearpaneUI/FullscreenToolPanelController.swift:35` 接收 confirmedControls，生产 `Sources/NearpaneUI/FullscreenPresentation.swift:147–156` 没有传入该参数，因此实际只有 NSScreen 安全区/刘海避让。不要把算法 fixture 通过称作智能避开工具按钮已经完成。

## 可复用的小范围实现

1. **几何与锚点**：复用 `DesktopWorkArea` 的逻辑坐标、`FloatingToolSurface` 的最小位移和安全区夹取。注意 Nearpane 主屏 `primary || .docked` 强制驻留，直接照搬将破坏 Saytile 主屏浮窗选项；其 WorkRect 是全高竖条，也不等于短语音板实际占用矩形。用当前 Saytile 的可见玻璃边界，不把阴影当占位，不引入完整 Spaces 或 8 窗平铺器。
2. **AX 安全语义**：`Sources/NearpaneUI/OrdinaryWindowManager.swift:39–40` 只管理显式确认且持续观测的窗口；同目录 `OrdinaryWindowAX.swift` 和 `Sources/NearpaneOrdinaryWindowController/{SystemEvidence,WindowMonitor}.swift` 绑定进程启动、窗口对象、公开 CG 几何；写前再核对；用户拖动期间拒绝；先保存恢复状态，再分步改大小/位置；歧义保留日志，不自动夺焦点。Saytile 可采用这些必要保护，不必引入该项目 IPC/Spaces 全架构。
3. **全屏呈现**：保留 Saytile 原文字板和唯一状态键，仅调节现有玻璃材质的遮蔽程度。Nearpane 全屏 NSPanel 是 32/56×26 或 136×34 的迷你工具条，`.regularMaterial` 位于 `FullscreenToolPanelController.swift:218`，不能当成 Saytile 产品 UI 搬来。`.fullScreenAuxiliary` 控制 Space 呈现，不保留屏幕区域。
4. **控件发现**：这是需补的真实能力。只在已确认的当前全屏窗口内读取 focused UI 的 role/frame，以及邻近 toolbar 浅层结构；不读 value/title/文本，不扫描文档/WebArea/ScrollArea。严格限节点、时间、邻域；未知时保留用户 anchor，不随鼠标追逐、不在选区/编辑/拖动中自动跳动。无 AX 时只能做屏幕安全区避让，不能伪称知道第三方控件。
5. **共存**：Nearpane 和 Saytile 同时运行时，不能让两个窗口管理器相互拉扯。保持单一窗口归属，或对已由另一个管理器接管的窗口停止调整；不能套两个自动平铺器。

## 权限与兼容性

- 普通窗口移动/缩放需要 Accessibility 信任与目标实现可写 AXPosition/AXSize；最小尺寸、不可写窗口、未知身份、隐藏/最小化、原生全屏或用户拖动必须拒绝/降级。不能通过抢焦点、反复写入或修改系统 Dock 设置保证边界。
- 仅用 CGWindowList 的 PID/window ID/几何和 AX 几何，不需要取得截图像素；不要为此主动请求录屏权限。
- `Sources/CReadOnlySpaces/ReadOnlySpaces.c:25–37,70–79` 使用 SkyLight 私有读取及 `_AXUIElementGetWindow`，只允许 arm64、OS build `26A428`。它不是系统保留区域 API，不宜移植为 Saytile 的公开兼容基础。改用公开 CG 号码与唯一 AX bounds 对应，重叠同 bounds 有歧义就拒绝。
- 新 App 窗口、全屏、权限撤销、系统升级均可能使约束不可执行；设置需如实报告有限兼容状态，而非把视觉边框叫系统隔离区域。

## 不碰用户窗口的验证

- 先运行纯几何 fixture：多屏/负坐标/刘海/浮板阴影/小窗最小尺寸/所有候选被占/用户锚点恢复。
- 用专用原生 AppKit fixture 自己创建合成窗口；以进程 PID + 启动身份 + 独立运行路径限定读写。参考 `Sources/NearpaneHost/NativeManagementAcceptance.swift`、`engineering/window-lab/Sources/NearpaneRegularFixture/main.swift` 的隔离做法。
- 覆盖首次位移、部分失败回读、用户手动变化、同 bounds 两窗拒绝、不可写/隐藏/最小化/全屏、权限丢失、关闭/PID 重用、显示器改变、恢复；未在 allowlist 的窗口必须零写入。截图只截 fixture 自身视图。
- 真正 NSWindow 原生全屏和 Space 切换不能用 headless 几何替代。采用独立 GUI 测试账户/测试 Mac 或明确隔离的次屏验收；此轮不在用户桌面执行。`FullscreenAcceptanceFixture.swift` 的合成状态只能证明呈现，不能证明真实全屏系统协作。

## 本次状态

- PASS：当前源码/分支/远端/权限和能力边界审查。
- NOT_RUN：这次没有运行 Nearpane 的原生窗口测试或重新复测旧验收计数。
- NOT_RUN：真实第三方控件避让，当前生产调用没有控件输入，需实现后再验。
- BLOCKED（平台能力限制）：第三方普通 App 无公开接口保证全系统任意窗口永不覆盖该区域。

公开 API 核对：
- https://developer.apple.com/documentation/appkit/nsscreen/visibleframe
- https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary
- https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue
- https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted
