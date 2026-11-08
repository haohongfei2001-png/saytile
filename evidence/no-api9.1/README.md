# Saytile no-api.9.1 实机验收

冻结源码 `0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0`。DMG SHA-256 `9d157becfa40e214b579036b03a178cffa85c96c6f0a54923809bd8110938339`。[下载候选](https://raw.githubusercontent.com/haohongfei2001-png/saytile/5ff88cb3ccf7c6ff4afb2f95360f5798d0be3632/deliverables/no-api.9.1/Saytile-1.0.0-rc.2-no-api.9.1-arm64.dmg) · [机器结果与收据指纹](snapshots/repeat-interrupted/machine.json)。

基线 no-api.9 显式选定内建麦克风时，计数探针复现了与产品相同的 AVAudioEngine 装配顺序导致的 SIGABRT。修补版只更改显式选定输入的硬件采集，默认设备和后续识别、存储、直接输入逻辑继承冻结基线。[修复提交](https://github.com/haohongfei2001-png/saytile/commit/0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0)。

| 项目 | 判定 | 实测与边界 |
| --- | --- | --- |
| 安装包连接内建麦克风 | **PASS** | 同一签名 App 的两段五秒硬件计数。DEVICE_PROBE hardware_buffers=50 hardware_frames=240000 sample_rate=48000.0 channels=1 no_samples_read_saved_or_recognized=true pinned_frames=239616 pinned_rate=48000.0。数据库录音与 WAV 均为零。 |
| 切换并在采集中移除双工聚合设备 | **PASS** | 使用真实 Core Audio 私有设备与产品选路代码。移除触发明确中断，恢复内建输入，系统默认输入保持一致。 |
| 切换并在采集中移除纯输入聚合设备 | **PASS** | 使用真实 Core Audio 私有设备与产品选路代码。移除触发明确中断，恢复内建输入，系统默认输入保持一致。 |
| 第二支独立物理麦克风拔插 | **BLOCKED** | 本次 Mac 只有一支物理输入；两个私有聚合路由均借用该输入。 |
| 受控睡眠和唤醒通知 | **PASS** | 生产 AudioController 转入中断，唤醒后重新检查明确的缺席设备，手动暂停时保持关闭。 |
| 暂停状态经历睡眠、唤醒后显示 | **FAIL** | P2：原本暂停时，受控唤醒后仍显示“Mac 已睡眠”，没有开麦或新增录音。 |
| 真实系统睡醒时进程存活、保持停采 | **PASS** | 共 2 对独立的内核睡醒时间与 Workspace 通知吻合。候选进程在对应唤醒记录中存活；另一个使用生产 AudioController 的观察进程只检查停采状态。 |
| 真实唤醒后重新检查指定的缺席输入 | **BLOCKED** | 未观察到可重新开麦的登录会话中完成缺席设备检查。锁屏、TCC 与会话许可会影响恢复，受控通知结果另列。 |
| 真实睡眠后继续物理语音 | **BLOCKED** | 没有隔离物理声源及可安全保存的环境讲话。缺席设备检查不能证明恢复真实讲话。 |
| 成品原生操作和非激活启动 | **PASS** | 45 次原生按钮操作、10 次菜单选择。UI 过程中观察到 2 次外部前台变化，日志均显示候选未激活；另一次专门的启动检查保持前台不变。 |
| 本机 NSTextView 所有权与错投防护 | **PASS** | 覆盖稳定范围去重、外部改字、新目标、选区变化、窗口关闭及重启。 |
| 生产前台选择 / 真实 TextEdit | **PASS** | 独立托管 Mac 上，仅新开的合成文档。核对首写、emoji、原有前后缀、连续增量、重复修订及选区变化。 |
| 前台 WKWebView 实际投递 | **FAIL** | 冻结客户端使用真实 WindowServer 前台窗口。FOREGROUND_INSERT kind=web result=unverified |
| 前台 WKWebView 目标变化、发送与重放 | **PASS** | 自有 WKWebView，页面身份变化后核对旧投递及发送计数。 |
| 隔离安装、升级、回退、卸载重装 | **PASS** | 公开 RC1 安装包仅用于临时目录中的模拟用户档案。未读取用户的已安装 RC1 或资料。 |
| 普通 Gatekeeper 执行 | **FAIL** | 严格代码签名校验 exit 0，Gatekeeper 执行评估 exit 3。个人工程包未取得 Developer ID 公证。 |
| 成品 Apple 本机识别 | **PASS** | 包内 App 识别合成中文、保存 WAV 并形成正式文字。 |
| 原生、AppModel 和协议回归 | **PASS** | 393 个原生测试函数，104 项 AppModel 检查，50 个本机协议用例。 |
| 首次两小时试验的档案指纹 | **FAIL** | 首次运行正常退出，80 段均定稿、原音有效、零丢帧；同一 Swift 构建目录被存储验证重用，试验后静态库指纹改变，原始 FAIL 保留。复测单独构建并核对实际执行文件、静态库、输入语料和源码。 |
| 两小时真实本地识别负载 | **PASS** | 实际 7200.58 秒，80 笔定稿、0 丢帧。 |
| 首轮驻留观察中断 | **BLOCKED** | 同一 PID 最后一次记录为 22.32 小时，共 1340 次。未取得退出原因或终态收据。独立测试库完整性 ok，录音 0。复测独立计时。 |
| 72 小时实际 App 驻留和进程资源 | **BLOCKED** | 3.04 小时，183 次采样，RSS 21,856–79,376 KiB，最大采样间隔 60.3 秒。到期 2026-11-11 19:23:51。 |
| 整机功耗归因 | **BLOCKED** | 仅取得当前测试 PID 的内核能量、CPU、唤醒和物理内存计数，整机 powermetrics 需要管理员权限。 |
| 真实云端认证、转写、质量收益及确认延迟 | **BLOCKED** | 真实调用为零。三项有效账户、相应模型权限和处理/费用授权、同一经许可的人声材料仍是前提。 |

在 3.05 小时内，这个暂停驻留进程的 CPU 时间占单核墙钟 0.238%，内核归因的平均 CPU 能量折算为 0.560 mW。物理内存占用的首、末十分位区间中位数分别为 18.6、19.1 MiB。整机功耗单独列为 BLOCKED。

真实云端待验证事项包括 Qwen 地域及 Workspace、AssemblyAI 模型权限、GPT-6 Astra 接收候选和结束定稿、同音频四阶段准确率及额外确认延迟。未进行付费调用或上传私人录音。
