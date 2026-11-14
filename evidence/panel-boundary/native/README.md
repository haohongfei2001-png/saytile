# 真实隔离窗口验收

2026-11-14，Apple Silicon macOS，真实 AppKit + Accessibility + WindowServer。最终 **28 PASS，0 FAIL，0 BLOCKED，0 NOT_RUN**。这不是全第三方应用兼容认证。

使用两份临时自有签名 AppKit fixture；生产 `PanelWindowAccess`、`PanelArrangementWorker`、`PanelCoexistenceController`、`PanelWindowEvents`、`VoicePanel` 源逐字编译。仅 AppModel 的三个设置字段为测试 stub；不打开数据库、录音、模型或当前安装 App。各轮准备使用一次显式命令，必要时做最多 3 秒的只读 AX/CG 就绪观测；不重试写、不自动重取焦点。调用受不可变 fixture PID allowlist 限制。另一个 fixture 的自身窗口 frame 前后相同；用户普通窗口没有被写入。完成后关闭 fixture 并按原进程启动身份恢复先前前台。前台 PID 记录未提交。

`source-binding.json` 固定测试所编译源及链接库 SHA-256；`verification.json` 确认所有六个测试/生产源与收口工作树完全一致。Git source_head 是收据产生时的基线；有未提交增量，因此必须结合逐文件 SHA，而不能单用该旧 HEAD 声称当前代码已验。最终提交由主任务统一记录。

## 实际验证

- 初次普通窗避让、重复幂等、浮板模式恢复、用户主动移到安全位置后不覆盖、取消前零写、隐藏板恢复、隐藏目标排除、同 bounds AX/CG 歧义拒绝、空间不足拒绝。
- 自有窗口实际在 AX setter 拒绝小于 minimum 的尺寸，生产写入真实回读并拒绝反复写；没有把 setter 返回成功当位置已确认。
- 真实生产 controller 启动、窗口再次进入面板下方、事件后重新避让、模式变更还原最新用户位置。该轮观察反应约 0.173 秒；生产同时有 AX observer 和 2 秒 fallback，不能单凭耗时把它说成纯 AX event 延迟。
- 自有目标 `NSWindow.toggleFullScreen` 进入真正 native fullscreen，目标不被移动/缩放，公开 AX 读到实际工具栏按钮。测试语音板偏好 frame `[1700,980,220,100]` 真正遮住按钮 `[1836,1028,80,52]`，交集 4160 pt²；生产 controller 自动移到 `[1700,920,220,100]`，尺寸不变、交集为零，并更新全屏呈现状态。退出全屏后状态与偏好位置恢复，原普通窗恢复归属仍保留。
- 不读取 AXTitle、AXValue、文档、网页正文或选区；不生成键盘/发送事件、不移动鼠标、不调用麦克风和 API。

## minimum 平台观察与失败历史

早期测试把“设置 NSWindow.minSize 后再拒绝缩放”等同于“frame 必须逐点保持不变”。真实数据否定了这个前提：请求 frame `[10,10,1900,1060]`，AppKit 声明 minimum `[1900,1080]`，实际 frame `[10,0,1900,1080]`，仍满足 minimum；生产 worker 返回实际 partial、blocked=1。**这不是 minimum 被忽略的证明。** 最终报告保留 `expected_unchanged_frame_status=FAIL` 作为平台观察，不将该前提伪装成已通过。产品 fail-closed 断言则用真正拒绝 AX 缩小的原生 fixture 验证，保留拒绝计数。

`history/` 不作为最终代码通过证据：

- Stage Manager 准备失败：AX 全尺寸和 CG 缩略图不一致，正确拒绝。早期部分轮次在对象尚不 on-screen 时失败，未写入。
- show 后系统调整测试窗位置：tiny-area 测试还拿旧 frame，当时断言 FAIL。修正为每项独立准备并读回，并保留原断言。
- native9：错误的 unchanged-frame 前提 FAIL；controller 很快排斥输入 frame，使 fixture 等待输入 frame 静止而超时。原报告总体曾误标 BLOCKED，现仅作为历史失败保留；当前聚合对任何真实测试 FAIL 优先返回 FAIL。
- 最初 full-screen 案例仅从按钮下沿拉开 8pt 间距，证明不足。最终改为屏幕坐标并增加正面积重叠断言，真正移动 60pt 完成遮挡解除。

无全局保留区域的系统 API，不保证任意第三方 App、最小尺寸冲突或 Stage Manager 缩略态都可调整。遇到 AX/CG 不一致、未知身份、拒绝或可用空间不足仍拒绝，不放宽身份保护。全屏呈现状态验收不替代视觉主观认可。
