# RC 音频工程工作记录

2026-11-06。基线 a371864，归属 Audio*/Speech*/CAudio 及对应测试；不修改其他项目、真实麦克风状态、系统电源或设备配置。旧 Beta 证据保留，不把既往测试扩写为真人或锁屏验收。

## 已确认根因与当前处理

1. 锁屏：目前仅监听用户会话切换，缺少独立锁屏通知和启动状态核验。采用成熟实现使用的分布式锁屏事件作为提示，结合 CoreGraphics 当前会话快照复核；解锁事件本身不会直接恢复。睡眠、会话、锁屏多个暂停原因分别保持，用户手动暂停优先。
2. 权限：当前仅通过无帧看门狗间接发现撤权。将加入只读授权状态巡检，撤权立即停止且不自动弹授权框。
3. ASR 定稿：当前未消费 `resultsFinalizationTime`，先前 volatile 结果只推进水位时可能被错误判为未完成。补充可测试的水位推进。
4. 识别尾部：识别侧 AVAudioConverter 未结束输入并排空尾帧，修复后再结束分析器输入。
5. 恢复调度：历史恢复仅完全暂停时启动，持续待命时资源下载前失败的记录可能一直等待。计划在静默待命时有限执行，讲话开始立即让路。
6. 语料：既有证据只有一条 TTS 中文，不能据此评估总体准确率、首字和断句延迟。建立可复现多类合成语料和指标；明确合成语音不等于真人验收。
7. 档案回听：补充跨分块的播放时长、当前位置、定位能力供父代理接入 UI。

## 验证约束

构建及测试独立目录 `/tmp/saytile-rc-audio`。测试使用独立库、TTS/合成音频及注入生命周期事件；不发布系统锁屏通知、不锁定用户屏幕、不外放。尚未进行的检查不得写为通过。

## 依据

- Apple CoreGraphics `CGSessionCopyCurrentDictionary`：公开获取当前窗口服务器会话的方法；SDK CGSession.h 定义 console/login keys。锁状态字典字段与分布式事件属于兼容性桥接，不冒称 Apple 稳定公开契约。
- Chromium 当前主分支使用 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`：https://github.com/chromium/chromium/blob/main/content/browser/screenlock_monitor/screenlock_monitor_device_source_mac.mm 。本项目自行实现小型适配，不复制其源码。

## RC 第一轮实现与验证

- 锁屏适配已经接入：分布式锁/解锁通知桥使用可注入 NotificationCenter；启动及每秒读 CoreGraphics 会话布尔快照，解锁通知不能覆盖仍锁定/睡眠/非当前会话的快照。授权撤回独立巡检并停止，自动恢复不请求新权限。仅本地注入事件和只读当前未锁会话验证；没有锁用户屏幕，也不标为物理锁屏实机通过。
- 识别结果现在消费 `resultsFinalizationTime`，先前 volatile 范围随最终水位定稿；识别端 AVAudioConverter 在关闭输入前排空尾帧。
- 待命静默五秒后允许有限恢复历史 ASR；讲话开始取消历史重试并退还恢复计次，录音不等待。普通 pause 保留恢复，shutdown 幂等取消并等待后台工作、关闭播放租约与识别生产者。
- 播放增加跨分块定位、当前位置、总时长；播放请求 generation 阻止过期 await 结果覆盖新请求/用户暂停；AVAudioPlayer回调核对实例身份，错误释放租约。
- 设备选择公开稳定 UID，重启按 UID 解析；未连接时明确失败，不自动回退默认。按 Apple SDK 要求释放设备名/UID 的 CFString 所有权。
- 修复恢复时超大稀疏 WAV 转 UInt32 崩溃；原音创建使用目录 FD 与 openat/O_NOFOLLOW，阻止 recording 目录符号链接在索引登记前越界写入。测试均为新建隔离目录。
- `Audio|Speech` 集中验证目前 **39/39，11 suites 通过**，见 `evidence/rc/audio-native-tests.log`。包括实后台线程 tap、文件故障、尾部 flush、锁事件桥、水位、seek、shutdown、超大文件/链接边界；不以这些测试冒充真人或真实睡眠设备验证。

## 中文对照与指标

八条自编语料、两种已安装 TTS 声音；没有真人/私人录音。使用同一批文件比较 Apple SpeechTranscriber 和 DictationTranscriber，没有更改实际输出、补词库或为样本定制纠错。

SpeechTranscriber：原样 CER **22.82%**；仅评价指标中统一数字/时间/标点/宽度展示后 **6.99%**。Dictation：原样 **19.42%**，展示归一 **6.45%**。Dictation 对 mixed 样本把 Swift 进一步误成 sweet，未形成明确优势，因此保留低延迟 SpeechTranscriber。数字展示归一规则、逐条结果和原样 CER 均保存，不能只引用较低数字。

首字 **1.18–1.24 秒**：按来源 buffer 时长逐块实时喂入，从识别 session 创建到首次文字。喂完全部 fixture buffer 到 completed **26–143 ms**，这是输入关闭后定稿耗时，**不是最后讲话音素/VAD 停顿后的端到端延迟**。Dictation 对照采用批量文件分析，仅对照质量，不比较延迟。

工程预设：展示归一 aggregate CER 约≤10%，否定语义另外核对；不等于用户真人验收。禁止发送、不是星期三/是星期四、不要取消会议等否定核心保留；原音/原因、mixed英文词和部分普通词仍可能错误。TTS的中英发音没有人工审听，不武断归因于模型或TTS。

重跑入口：`scripts/test-audio-corpus.sh`、`scripts/summarize-audio-corpus.py`；证据 `evidence/rc/audio-corpus*.json` 与 `audio-dictation-comparison.*`。

## 长稳进行中

30分钟墙钟合成 ring→AVAudioConverter→WebRTC VAD→WAV/SQLite 已在 `/tmp/saytile-rc-audio/realtime-probe` 启动，独立库 `/tmp/saytile-rc-realtime-data.rajnLf`。不打开麦克风或扬声器、ASR关闭。日志 `evidence/rc/audio-realtime-30min.log`；完成前不记录通过。该探针于本轮首个音频checkpoint启动，其后文件路径加固和退出清理另有专项回归；不将运行中的旧二进制冒称最后发布包。

## 30 分钟墙钟流完成

实际 **1800.42 秒**运行，输入 **39,690,000 frames / 22050 Hz**，C ring 丢帧 **0**；60条封段，保留原音 **1800.0 秒**（浮点求和误差约2e-12），57,607,876字节，全部 available/finished，60项待识别留在磁盘队列。CPU user 15.20s + sys 7.78s，约 **1.28% 单核平均**；max RSS **22.89 MB**，独立的 peak memory footprint **65.26 MB**。这两种内存口径分别保留，不混用。

结构化证据 `audio-realtime-30min.json` 与原始time输出 `.log`；探针二进制SHA256已记录。此为不含ASR/UI/整机功耗的合成管线长稳；非真人/麦克风、非72小时，亦不冒称最后发布App本身运行了30分钟。

独立存储代理复核音频路径加固、UID失联和shutdown未发现P1；其发现的播放A→B丢失原收音恢复意图已修复，替换播放准备失败也保留恢复意图，并仍受用户pause/generation约束。

## 实际静音播放器集成

追加 **2/2** 生产 `AVAudioPlayer` 集成通过（独立 `AudioPlayerIntegrationTests`，0.543秒），见 `evidence/rc/audio-playback-integration.log`。测试创建纯零PCM WAV并调用 `AudioController.play`：跨块/反向seek、自然结束、stop与shutdown、播放期间原音删除的租约延期及文字保留。没有采集麦克风、没有有声外放，也没有自动启动收音。此为实际播放器验证，和前述纯timeline测试分别记录；此前39项集中测试与本次2项独立运行，未冒称已经重跑聚合41项。
