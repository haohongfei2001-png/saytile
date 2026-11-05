Always-On Voice / 声迹 — 工程交接草案
设计日期：2026-11-05

一、交付边界

这是产品设计附带的接口与数据实验，不是可安装的 macOS 软件，也不是正式工程。
contracts.swift 是尚未编译的接口草案；没有实现麦克风、ASR、持久化或辅助功能操作。
方法名表示应用内部边界，不应当作 Apple 或第三方 SDK 的同名 API。

reliability_lab.py 的 10 项检查只在 Linux 上使用合成 PCM 与 SQLite。
它们不是 M5 Air、macOS/APFS、AVAudioEngine、SpeechAnalyzer、Core ML、
真实输入框兼容性、断电或电池续航的验证。结果见 reliability_results.json。
实验音频为 16 kHz，便于固定数据集；产品设计归档设备实际采样率的单声道
16-bit PCM（典型内置麦 48 kHz），两者不是同一个实测对象。

二、文件与运行

  schema.sql                 可执行的拟议 SQLite 数据结构
  contracts.swift            未编译的 Swift 模块接口草案
  reliability_lab.py         标准库即可运行的小范围故障实验
  reliability_results.json   最近一次实验输出

从 handoff 目录运行：

  python3 reliability_lab.py > reliability_results.json

从交付包上一级目录运行：

  python3 handoff/reliability_lab.py > handoff/reliability_results.json

需要 Python 3 和支持 FTS5/trigram 的 SQLite。实验使用临时目录，不访问麦克风，
不修改用户语音历史，不访问外部输入框。子进程按实验安排以状态码 47 退出；
整个脚本成功应以状态码 0 结束，JSON 中 passed=10、total=10。
若 Python 所带 SQLite 没有 trigram，实验会失败而不会伪报通过；产品本身应
运行时检查能力，并用经过转义的参数化 LIKE 降级。

三、唯一主栈与备用

最低目标：macOS 26+、Apple Silicon、Swift 6；首要设备 M5 Air / 24 GB。
界面：SwiftUI + AppKit（NSStatusItem、NSPanel、焦点、多屏）。
采集：AVAudioEngine + Core Audio 设备管理 + AVAudioConverter。
VAD：FluidAudio 0.18.2 的 Silero Core ML 路径；当前 4096/16k 窗口为 256 ms。
主 ASR：Apple SpeechAnalyzer + SpeechTranscriber；运行时检查设备、locale、
installedLocales 与 AssetInventory，不能用“macOS 26”代替资产就绪判断。
不用新 Beta 采集助手作为最低版本依赖；使用 AnalyzerInput 音频流。
唯一备用：Argmax OSS Swift 1.1.1 中的 WhisperKit library product，按需加载
openai_whisper-large-v3-v20240930_626MB 多语言 Core ML 模型（目录约 627 MB）。
下载大小不等于工作集；不同时常驻两套 ASR，不自动上传失败语音。
持久化：文件 + SQLite WAL/FULL；正式工程使用 GRDB 管理迁移和观察。
输入：Accessibility 局部插入或已绑定目标的 Cmd+V；不发送消息、不写回全文。
登录：SMAppService；P2 才接入 Sparkle 2、Developer ID、公证及升级流程。

工程启动时锁定 package 版本与模型 revision/hash，并按产品报告逐项保留许可证。
WhisperKit/Whisper/指定转换模型 MIT；FluidAudio Apache-2.0；Silero 及具体
转换模型仍按对应模型卡核验。代码许可不能代替模型权重许可。
SenseVoice 不作为首版默认再分发：代码 MIT，权重适用 FunASR 模型协议，
README 商用说明与后续许可澄清状态不可混作“全部已按 MIT 解决”。

四、实现必须保持的约束

1. 唯一 realtime tap 只复制到预分配 SPSC，并更新必要的原子计数。不得在
   回调内分配 Data、await、写盘、调数据库、运行 VAD/ASR 或刷新 UI。
   非实时消费者负责有界批次、转换、VAD、文件和任务协调。
2. 原音是单声道 16-bit 恢复录音，不承诺硬件位级原样。VAD 使用独立 16 kHz
   分支；ASR 查询最佳格式并转换，保存采样时钟与引擎时间之间的映射。
3. 每个物理 PCM 块最长约 15 秒，只含同一个 epoch 的连续样本。丢弃中间
   静默后另开块。约 30 秒为软检查点；约 5 分钟的长讲话才考虑 ASR 轮换。
4. 文件/sidecar/必要目录项先同步，再提交 SQLite，之后才显示对应范围已保存。
   约 1 秒未同步窗口是正常 I/O 下的目标，不是断电、磁盘故障或阻塞时的保证。
5. utterance_audio_refs 显式保存 core/context 到物理块的范围映射；范围为
   同一 session 内的绝对样本索引 [start,end)。写入事务校验 session、块边界、
   durable/recovered 范围，不把单个“最大水位”误当作连续无缺口覆盖。
6. 删除先提交 deletion_tombstones 并取消任务。全删同时推进 generation；
   单条/范围删记录 session 和样本范围。恢复先读取这些标记，再扫描孤儿。
   tombstone 不通过外键依赖待删除记录，物理清理完成前不得移除。
   删除共享块中的部分范围时，可按字节复制未删除范围到新块，切换引用后
   移除旧文件；仅删数据库引用不能宣称原音已删除。磁盘错误应显示待清理。
7. 一次一个 ASR worker；当前讲话优先于旧重试，采集永不等待它。任务只存
   音频引用。失败保留已显示文字；按 attempt + generation + 未删除状态
   在同一个事务接收回调，拒绝旧结果复活。
8. SpeechTranscriber 的 volatile 结果可被替换；稳定水位会前进，而同一文本
   不保证再次返回 isFinal=true。封段结束输入并 finalize 后仍要排空结果流。
   原始 ASR、用户编辑、AI 版本分离；不按文字相同去掉真实重复讲话。
9. 临时版本有界保存；被编辑/插入引用的快照不可原地改写。输入范围使用
   UTF-16 偏移并校验边界。自由记录不依赖输入目标或辅助功能授权。
10. 绑定目标只在当前输入会话有效；重启/重绑使旧 prepared 自动操作失效。
    dispatching 崩溃后变成未确认，不自动重发；不锁住后续独立操作。
    非空选区需要明确追加后方或替换选择；未知选区只复制。终端首版仅复制。
    “已复制”与“已插入”分开；剪贴板不能用固定 100 ms 延时盲目恢复。
11. 原音默认最多 30 天、最多 10 GB；容量可使未保留的已完成音频提前过期。
    未识别/失败/用户保留以及正在使用的范围受保护。保护内容占满预算时
    明确报告不能继续保存，不静默删除，也不无限扩张内存。

五、现有 10 项实验实际覆盖什么

  1) 同步 PCM 后、登记索引前退出，孤儿音频可找回。
  2) 尾部多一个不完整采样字节时截尾恢复。
  3) 拟议 schema 能执行且 foreign_key_check 无错误。
  4) 同源/同模型/同请求版本任务重复入队保持幂等。
  5) 两次相同讲话仍为独立记录。
  6) 迟到 ASR 新版本不覆盖用户选定编辑。
  7) 旧 attempt 完成事件被拒绝。
  8) 旧 generation 完成事件被拒绝。
  9) 未确认插入不重放、也不全局阻塞另一操作。
 10) 三字 trigram 与两字 LIKE 查询各能找到中文结果。

第 9 项模拟“下一项可独立操作”的数据库状态，不证明 prepared 操作可以在
真实应用重启后自动派发；真实实现仍须用户重新绑定/主动调用。
新加的音频引用与 tombstone 表随第 3 项完成语法检查；现有 10 项没有实现
共享块范围删改、完整孤儿 tombstone 恢复、并发设备切换或原生输入。这些
是下一步工程验收，不应把此次 PASS 扩大为对应产品能力已完成。

六、第一原型：在目标 Mac 上完成的最小闭环

先做一个菜单栏进程 + 小型调试板，完成麦克风 → VAD/预录 → PCM/SQLite →
Apple ASR → 实时文字 → 手动复制。不要先做账号、云同步、Windows 或 Agent。
按以下顺序验证，不要求用户自行选模型或制作测试集：

  A. 首启明确开启麦克风；暂停真的停止采样；锁屏/睡眠有分界；断网仍保存。
  B. 连续讲话 30 分钟，前段识别阻塞时仍收录后段；文件与采样范围可追踪。
  C. 随机杀进程并重启，核对已确认原音范围；注入 ASR 错误后可以重识别。
  D. 短“嗯/好/对”、长停顿、连续长句、混英、数字/否定词与专业术语语料。
     同音频比较 Apple 与唯一备用；报告 CER/术语命中，不编造质量排名。
  E. 在 M5 Air 测首字/停顿后定稿 P50/P95、RTF、模型工作集、静默增量功耗，
     区分应用进程和系统模型服务；所有目标值以报告为预算，不是已获成绩。
  F. 之后再接明确绑定的 ChatGPT 输入：保留已有正文/附件，不发送；换聊天、
     选区、剪贴板竞争、崩溃后未知提交均有明确降级，插入失败不影响原音。

第一轮设计预算约 8–12 个有效工程日；若中文混说、待命功耗或连续表达体验
没有达到继续投入门槛，应依据这轮结果修订路线。当前交接包本身不证明达标。


附加设计文件
- design_tokens.json：视觉规格、排版、状态色与尺寸。
- SOURCE_URLS.txt：报告的一手资料索引。
- prototype_checks.json：22项浏览器演示交互检查结果；不等于真实macOS权限、识别、录音或外部输入验证。
- ui_checks.cjs：可选浏览器回归脚本；在交付包根目录运行，需要可用的Playwright及其Chromium。可通过 AOV_BROWSER_PATH 指定已有浏览器。此脚本只操作包内HTML演示。

打开 always_on_voice_prototype.html 可直接评审七个场景，无需启动服务器。
完整产品与工程理由见 Always_On_Voice_Design.pdf。

VAD资源部署：将已固定版本和哈希的Silero Core ML资源随应用打包，使用SDK本地加载路径；不要在检测到讲话时才自动联网下载。保留模型MIT与SDK Apache-2.0声明。
