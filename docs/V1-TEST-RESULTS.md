> **PR #6 · no-api.6** 已在源码 `455143310222c2c03c4a4888e5df5552c3af4131` 构建实际 DMG；原生套件 392/48/512、AppModel 104、localhost 三服务及实际 DMG 的 UI、系统输入、Apple 本机识别、升级和回退均已执行。当前快照先保留已结束的短项，长跑不计为通过。在同一冻结 SHA 的实时时钟采集自然退出后才补充整段波形与总状态。[安装包](../deliverables/no-api.6/) · [证据范围](V1-NO-API-DELIVERY.md)。

> **冻结前预览**：真实 Mac App 37 张截图、45 个 AXPress、10 次菜单选择、11 次底部双控件检查通过；AppModel 104 项、生产采集 VAD 与受控延迟定稿专项通过。原生操作确实执行，无前台激活；采集界面依赖注入，未使用麦克风或真实服务商。两个预览中的误判均在[预览证据](../evidence/bottom-controls/preview/)保留。最终同 SHA 结果单列。

> **底部面板接续 · 2026-11-07：** 底部控件的预检：真实独立 AppKit 文本窗口使用 AXShowMenu / AXPress 打开并选择菜单；生产 AppModel 到独立 NSPasteboard 的两种 Unicode 复制逐 UTF-16 相同，均未启动或暂停采集。见[原生菜单](../evidence/bottom-controls/context-menu-preflight/)及[独立粘贴板](../evidence/bottom-controls/copy-preflight/)。仅属于工程预检，非最终候选包验收。

> PR #6 当前：4df87ad4基线的完整本机原生391函数/511场景、97 AppModel、50 localhost网络case、安装8+2及1800.54秒逐帧保存均通过；全部28,800,000帧与参考相同。此证据不能充作新版底部控件/三态验收。 [已闭合的4df工程基线](../evidence/no-api-product/final-no-api5-r2/BASELINE.md)。

# 当前分层结果 · 2026-11-07

702a24b9 首次集成：[不交付原因和原始结果](../evidence/no-api-product/final-no-api5/HOLD.md)。391函数/47套件，1项静音回听固定180ms采样失败，三服务协议12函数/52场景通过。本机97 AppModel、输入DOM20/原生9+受控改字5/owned9、Apple合成8、原生控件36图/45 AXPress、安装升级8与卸载重装2通过。两条远端CI通过，不覆盖本机失败；原始红灯保留。

最终已验基线为1067f1ad / no-api.4：386函数/46套件/506场景（包含50 localhost网络case，零peer违例）、78 AppModel、DOM20、原生AX9+接收方改字5+owned-range9、Apple合成8、控件31图/41AXPress/12组、另20只渲染图；数据进程12、升级8、卸载重装2通过。原生与设计CI均成功。

新的1800.48秒生产保存链合成运行：60段/179个WAV，28,800,000帧与独立参考全部逐字节相同，差异0，23/23最终检查通过；40采样RSS15,136–18,512KiB、22.93 CPU秒。无麦克风/ASR/扬声器/云调用。包空闲另测300.03秒；不能相加为真人质量或整机功耗结论。

后续no-api.5按新批准UI接续。阶段性状态97项、目录隔离9项已通过，最终整合SHA全量回归未完成；原图比对也未完成。所有不同层/不同SHA计数不相加、不互相代替。WK写入仍UNVERIFIED，生产前台resolver未执行，真实云连接和质量未知。

[完整分层表与原始证据](V1-NO-API-DELIVERY.md)。整体NO_API_ENGINEERING_READY尚未授予；LIVE_CONNECTION_PENDING。

原生阅读边界复审：上滚2pt后的追加不再跳底，保留复现及修复结果。最终包将同时验主动回底后的正常跟随。

702a回听修正专项：真实进度订阅在0.106812秒收到正值0.0856875，两个原生静音回听检查通过；只改测试同步，无生产源码变化。随后使用新的整合SHA执行完整同版本验证。

<details>
<summary>历史检查点（旧状态、模型组合和预算不适用于当前交付）</summary>

> no-api.4 收口修复完成，准备重新冻结：UIReview 双可选闭包导致纯渲染误调用控件，已用独立入口根治（本机Swift6.4也复现原语义，并非已证实版本差异）。全部后台测试窗禁止key/main、透明且忽略鼠标；原生9+接收方改字5、owned-range9、WK6/2/0、UI两模式20/31图通过。原a684首个AX失败来源仍未确定、CI红及536.05秒主动中止长跑完整保留，不当作最终通过；未改生产输入保护。接下来在新SHA先完成短项与CI，再跑30分钟全波形。当前无需用户操作。

> 原生恢复按钮补验完成：实际AX点击“已暂停→继续收音→聆听中→暂停”，共41 AXPress；31图、6菜单动作、5热区/语义检查、12组交互通过，0焦点变化。原39次检查点完整保留，随后冻结整合源码执行最终全套验证。

> no-api.4 紧凑文字输入板工程检查点：原生31图、39 AXPress、6菜单动作、5热区/语义检查、12组交互通过；AppModel78、窗口几何10、独立Unicode10+选区/滚动5通过。已修规范等价导致UTF-16漏更新和中断原因呈现；菜单异步投递改以真实状态确认。下一步提交冻结后执行同SHA全部最终验证，尚非本版最终就绪声明。无需用户操作，0真实云请求。

> no-api.4 紧凑文字输入板正在实施与原生交互收口。已验no-api.3证据保留；新候选须完成同一整合源码最终验证后才能交付。当前无需用户操作，无真实云端调用。

> 最新接续：发布时收到并保留5d55d74d的紧凑文字输入板目标，尚未实装；当前no-api.3仅为已验工程基线，继续UI实施与回归，不宣称最新V1目标全部完成。无需用户操作。

# no-api.3 最终分层验证 · 2026-11-07

**NO_API_ENGINEERING_READY / LIVE_CONNECTION_PENDING。** 最终运行时`ef2f8f84f377197350e6384f79af12a9b56272fd`。30分钟墙钟1800.42s，60段/179个WAV，28,800,000帧完整逐字节相等，差异0；无缺帧或多余尾帧；保存拼接PCM与独立参考的SHA256一致（050b5e8b…85385）。全部检查及源/探针/输入hash见final/local/realtime-assessment.json。

379原生函数/46套件/499展开场景（零跳过，包含50真实localhost网络case）、66 AppModel、DOM20、原生AX9+9、Apple合成中文8、原生22图/34 AXPress/6字段/9组控件、存储进程12、安装升级8、卸载重装2全部通过。包待命300.023s，1.74user+0.35sys秒，暖态RSS59,248–80,288KiB；非抢焦点启动通过。两项运行时CI成功，CI渲染与本机真实控件证据严格区分。专项/参数化与全量不重复相加。

[完整交付与证据](V1-NO-API-DELIVERY.md)保留真实云端未调用、前台resolver NOT_RUN、WK写入unverified、历史AX UNKNOWN、物理生命周期/多显示器/长期功耗及未公证边界，不等于PRODUCTION_READY。旧no-api.2已撤回；main/RC1/用户资料未改。没有用户临时测试事项。

以下是历史检查点，不用于替代本次最终源码证据。

---

# no-api.3 音频块归属修复已完成 · 2026-11-07

新转换循环持有从ring读出的音频，直到AVAudioConverter输入回调实际领取，再读取下一批；缓存输出按原顺序保存，不补零、不改变采样策略。新增四采样率完整波形回归先红后绿，22050Hz由41153/44125帧恢复为44125/44125且逐字节一致；14测试/5组专项通过，两位独立审查通过。

下一步提交本次修复并在同一新SHA重跑全部最终验收，版本no-api.3。no-api.2保留并明确暂缓交付，历史绿灯不覆盖确证的原音漏块；原始证据仍可复核。无需用户操作，尚不宣布NO_API_ENGINEERING_READY，真实云端LIVE_CONNECTION_PENDING。

---

# 音频块归属缺陷根治中 · 2026-11-07

冻结运行时d4b9dbe的378原生、66 AppModel、协议、UI、安装及30min文件/数据库检查通过后，输入波形对照进一步确证中途缺1486帧。最小触发已复现：converter直接输出旧缓存时inputBlock未调用，旧循环已从ring取出的新块却被释放。no-api.2暂停交付，旧审计READY建议撤回；不归因VAD或正常重采样。

正在最小修复输入所有权（持有buffer直到converter实际领取，不补静音掩盖缺口），加可变块与完整参考波形回归，然后构建no-api.3并重新执行最终统一源码验证。原始证据保存在evidence/no-api-product/intermediate-d4b9dbe与audio-buffer-ownership。main/RC1不变，无用户操作或真实API调用。

---

# 补审修复与新冻结准备 · 2026-11-07

3f49682c 的完整本机测试和包验证保留为中间证据，不能替代新源码验收。补审确证并正在关闭：首次开通云端可能自动上传旧本地失败原音；换密钥可能把旧音频发送到新账户；VoiceSegmenter 的 Data 前缀存储可能随音频增长。修复采用录音级目的服务/地区/Workspace/凭据身份授权、schema5 无授权回填迁移、本机恢复回退及不足一帧尾部深拷贝。原生档案明确区分“本机重新识别”和“用云端重新识别”。

当前 controller/工厂/正式采集专项已通过；Store、凭据代次和内存专项正在整合。随后提交 no-api.2 运行时并在同一 SHA 重跑完整本机网络、原生/Apple/AX、升级回退、打包和30分钟合成墙钟测试。旧计时断言红灯保留，已改为从真实请求/取消事件计时，不放宽生产截止时间。当前尚不宣布 `NO_API_ENGINEERING_READY`；真实云端仍为 `LIVE_CONNECTION_PENDING`。main/RC1 不变，无新增用户操作。

---

# 最终运行时冻结准备 · 2026-11-07

PR6 检查点12ce5eac已远端保存；本轮后续修复真实原生连接设置的展开/费用交互，完整空配置→三安全输入框→授权→成功/失败/取消的实际原生交互已通过：22图、34次AX点击、6次字段输入（含3个安全字段）、9组操作。成功状态仅用TEST_ONLY结果注入，非实网验证。CI全量并发暴露的短超时、首显轮询、取消任务数量假设已改为明确事件与任务归属断言，未减少生产安全校验。红灯记录保留，不重跑旧SHA。

下一步：提交整合运行时，再在同一SHA执行带本机服务端的完整Swift套件、AppModel55、原生控件、Apple/AX、SQLite升级回退、30分钟合成墙钟采集、打包及安装。真实云端仍LIVE_CONNECTION_PENDING；此时尚不宣布NO_API_ENGINEERING_READY。无需用户参与，RC1/main不变。

---

> 本轮检查点：364 项原生/42组通过（另11个协议函数须服务端，因此单独执行51场景网络验证，不混算），55 项 AppModel通过；原生预览15视图/6组控件通过。当前仍在补充完整连接向导控件、统一SHA最终回归和安装包验收，尚非最终就绪声明。

# PR #6 本轮证据 · 工作检查点 · 2026-11-07

本轮新证据位于 evidence/no-api-product；下方历史计数不得视为本轮最终结果。ASR 协议专项 39 项/3组通过；真实 localhost 正式网络客户端已复现并修复断线与错误分类，完整向导预算与 EOS 正在回归。实际后台 AX 扩展9场景通过；Apple已安装资源8条合成语料全部完成统一候选发布，但存在识别错误且已披露。以上是中间快照，最终集成SHA仍待完整重跑。

严格分类：单元/模拟器不是云验收；本地 Apple 合成音频不是用户真人讲话；辅助功能fixture不是任意外部应用认证。真实云端 LIVE_CONNECTION_PENDING，质量未评估。

---

# RC2 candidate.2 最终包验证 · 2026-11-07

源码 7320228、干净包 binary d109e060、DMG a218c4c9。286 native / 34 suites、25 AppModel；最终包 15 原生视图/6 控件组（16 AXPress+2 AXSetValue+2 native editor）、7 设置 CLI、4 回放 CLI、8 实际 RC1 安装升级回退均 PASS。所有包证据绑定同一个从只读 DMG 复制的可执行文件。120.042 秒隔离待命，1.07 user+0.21 sys 秒，最大 RSS 105,725,952 字节；采样暖态 RSS 73,904–102,416 KiB、末次 93,168 KiB。此结果无 ASR/麦克风，不证明功耗或长时稳定。旧普通持有进程偏好隔离缺口已纠正，新回执确认全部禁用。证据：research/asr/validation/rc2-no-key/delivery-manifest.json。

运行时远端 macOS CI42287027227与设计契约CI42287027237均已成功；Swift6.3.3实际日志确认286项原生、25项AppModel及构建/CLI/15视图/启动。纯证据最终head的检查随后记在PR正文，保持同一运行时包。

---

# RC2 无密钥补审回归 · 2026-11-07

**286 tests / 34 suites PASS、25 AppModel checks PASS**，完整最终源码集成日志为 `research/asr/validation/rc2-no-key/native-final.log` 和 `app-model-delivery.log`。待删目录专项为 66 项 / 6 组，与全量重叠。真实 000 目录、已完成删除后的残留、SQLite 事务中断及恢复错误清理均已验证；取消/恢复交叉路径由另一负责人独立只读复审，未发现新的具体 P0/P1。

测试隔离修正：过去 `--data-directory` 普通持有进程仅隔离数据库，可能使用标准偏好；旧升级/待命记录不能被扩张为偏好已隔离。现已修复正式启动分支，新的持有进程须证明云关闭、后台识别恢复关闭、无快捷键与首次窗口。旧包没有因此重新计为通过，后续 clean candidate.2 包结果单独记录。包内 RC1 旧安装指引已修正为 RC2 候选与完整副本回退说明。

---

# RC2 无密钥完整回归 · 2026-11-07

最终集成源码：**283 tests / 34 suites PASS**（`rc2-no-key/native-all.log`），**25 AppModel checks PASS**（`app-model-final.log`）。专项 63 / 53 / 21 项与全量重叠，不相加。首轮红测、编译重叠中止和后续绿测均保留，不以重跑删除失败证据。

- 真实独立文件/SQLite：0400 WAV、000 记录目录、最后一步 SQL abort 和 chunk reconciliation abort；失败事务回滚，原音及用户稿保留，其他记录继续恢复，权限恢复并重启后幂等修复。有效只读 WAV 无需写权限。
- 并发：最终化中显式取消与 watchdog 均取消并等待独立复核退出；Store 不残留运行状态，不发布取消后候选，既有文字/原音保留。生产 deadline 仍 480 秒，不声称强制终止不配合取消的代码。
- 生命周期/喂音：首次授权待定仅在 starting 时保留；锁屏/会话状态在等待后重查；保存音频按实际 PCM 时长回放；拒绝通道和采样率不匹配的 tap 数据并记录中断。未实际操作系统权限或物理设备。
- 刷新：40 并发请求实际读库次数由 40 降到 2，用户编辑稿与退出边界通过。
- 120 秒真实墙钟合成采集：1,920,000 source frames、0 ring drops、40 records available/finished、119.92 秒 VAD 原音、3,839,200 字节；user+sys CPU 1.43 秒、最大 RSS 21,626,880 字节。来源快照见 manifest，早于最后采样率 guard。ASR 关闭，不能证明真实收音/云端/72 小时/整机能耗。

详见 [本轮证据索引](../research/asr/validation/rc2-no-key/README.md)。干净包与新 CI 待随后记录，不复用旧包结果作为新包通过。真实云端仍 NOT_RUN。

---

# RC2 干净候选交付检查点 · 2026-11-07

最终干净包：15 张真实原生视图、6 组实际控件交互 PASS（16 AXPress、2 AXSetValue + 2 原生编辑器提交），7 项连接设置 CLI、4 项回放隔离 CLI、8 项实际 RC1 DMG 升级/回退 PASS。候选从未激活；测试期间记录 1 次外部前台转换，未归因，不声称全程前台不变。270 项原生 / 32 组与 23 项 AppModel、43 项离线评分是各自层次，不合并计数或冒充云端实测。完整 [证据索引](../research/asr/validation/rc2/README.md)。

输入分层：9 项后台原生 AX、20 项 headless DOM 通过；真实 WebKit 的 6 类目标失效和禁止自动发送通过，但后台 AX 写入值未变，单次投递标 unverified，不作为成功插入。前一轮未归因焦点变化日志及唯一带归因复测保留；复测 owned activation=false。

---

# RC2 工程收口检查点 2 · 2026-11-07

本机完整 270 项原生 / 32 组 PASS，含 4 项连接导出/隔离用例；开发包实际 7 项 CLI 拒绝检查 PASS。实际原生界面 15 场景、6 组交互通过：16 次 AXPress、2 次 AXSetValue 加 2 次窗口内 field editor 提交，无全局按键；Finish 拒绝未准备配置。该证据使用合成数据与开发包；最终干净包的交互、安装和升级另行记录。原始 UI 失败、CI 编译器崩溃及修复依据全部保留。

---

# RC2 工程收口检查点1 · 2026-11-07

RC2检查点1：本机266项原生/31组PASS，23项AppModelPASS，43项既有离线评分PASS（只防回归，不做新排名）。独立复审真实复现2项取消所有权P1/3个断言失败并验证修复，红绿日志保留。12项实际子进程/旧版本升级/崩溃/显式备份回退PASS；8项旧RC1 DMG→preview76e通过但尚不是最终RC2包验收。原生控件验证继续中：AX赋值不是SwiftUI编辑提交，已用独立NSHosting实验证明原生field editor提交路径；外部前台切换与候选激活严格区分，不以一次未归因记录归咎用户。

---

# 评分与候选最终检查点 · 2026-11-07

评分43/43 PASS；16类整句来源拒绝子场景，包括配置ID错配/缺失。新增单位8项/10次出现来自独立冻结参考，非按识别结果挑选。原112条manifest散列未改。失败与修复后日志evaluation-scope-before/after保留。运行时76e89c2 native CI42247755214通过252项/25组、21AppModel、4项CLI；contracts42247755189通过（当时26项评分）。本机该干净运行时构建、严格签名、隔离smoke、CLI4通过。旧焦点未归因记录保留，未对新版重复声称焦点验证。全部云质量/延迟/收费调用仍NOT_RUN或0实际调用。


参考补审扩展为新增数字34项/36次、否定26项/28次（全部112条仅据参考审阅），单位8项/10次不变；标签有散列和逐项原文范围，原件不改。新增4项同音频延迟配对测试，保留缺失/失败并按语言汇总增量。

---

# CLI隔离收口检查点 · 2026-11-06

新增实际CLI4项PASS：缺目录、缺目录值、下一参数是flag均exit64；显式独立目录+关闭云配置exit1，records/model_runs均0。脚本check-probe-isolation.py及JSON已保留，已加入native CI。此验证未打开个人库、未读音频、未查凭据或发网络请求；启动恢复并发修复另经代码审查，不伪称实际云回放通过。

---

# PR #4 源码CI与候选交付 · 2026-11-06

远端源码1c907f6与本机252测试使用的87395e6整树同SHA。macOS26 native run42241293084成功（252项/25组、21AppModel、构建、合成原生窗口、隔离启动）；contracts run42241293137成功。sourceDirty=false的未安装preview.2 release/signature/smoke通过。26项离线评分现加入Ubuntu工作流，无云调用。

焦点验证不掩盖混合观察：首候选通过；远端同树身份重打包后一次发生前台改变，未归因；随后唯一一次带候选PID归因复测通过，候选从未前台且其他切换为0。证据保留，未据此声称长期无干扰或把失败归咎用户。真实识别精度/确认延迟未测。

---

# PR #4 集成回归检查点 2 · 2026-11-06

最终本机252 tests / 25 suites PASS，21项AppModel PASS，26项Python计分/来源/配置/准备入口测试PASS；继承契约验证通过。完整证据与失败记录在 `research/asr/validation/fusion-quality/README.md`。全量覆盖Store失败状态派发禁用、当前全部证据重验、未派发纠正、实际派发前缀、多目标、用户草稿、取消删除、真实终态、被拒绝仲裁审计和纯本地基线身份。

未以相交专项计数累加总数。独立审查从旧静态构建复现failed-expert→reserve缺陷，修复后同用例前后两个时点都NONE；首轮并发全量失败与最终绿结果均保留。真实云请求、准确率增益、确认延迟和账户费用仍NOT_RUN。

下一步只构建此提交的未安装候选并检查CI；CI并不能取代上述未测能力。

---

# PR #4 融合质量检查点 1 · 2026-11-06

- 新融合发布边界与原有多模型：41/41 通过；仲裁证据与英文协议：27/27 通过。新用例分别 9 与11项，交叉筛选计数不得相加当全量。
- 先复现：短复核错误宣布解决、Meta progress 被当音频范围、尚未派发定稿无法修正；red 日志保留在 `research/asr/validation/fusion-quality/`。
- 新协调器集成7项（其中两个参数化各2例）通过，包括未派发全文纠正、同PCM不重复音频复核、新PCM重查、实际派发保护、失败保留。首轮241项全量曾因并发旧状态触发不必要仲裁失败1项，修复后待最终全量，不隐藏失败。
- Corpus只读哈希：112/112，832.1804375秒；未采集麦克风、未上传语料。Keychain仅元数据、禁止弹授权、0匹配；没有读取秘密值。云模型准确率、服务可达性和真实延迟未测。

以下为RC1历史验证，计数不覆盖本轮源码。

---

> **最新 RC1：源码 `8906a9d` 在 macOS 26 上 122 项原生测试、21 项 AppModel、构建/原生渲染/启动通过；最终 DMG 安装升级 6 组、9 图/5 次 AXPress、合成中文与安装后启动通过。下文保留完整历史与失败，不将旧计数作为最新。**

# V1 验证记录

## 2026-11-06 · 基线

- PR #1：远端 data-and-prototype / swift-contracts 全部 SUCCESS。
- 本机 `python3 scripts/check_integrity.py`：66/66 文件一致。
- 本机 `python3 tests/test_recovery_contracts.py`：37/37 通过。
- 本机 Swift 6 契约 + SwiftSmoke：8/8 Unicode 断言通过。
- 环境：macOS 27.0 (26A428)，arm64，Swift 6.4，Command Line Tools SDK。

这些是继承设计契约验证，不代表原生 App 已可用。原生验证将在实际执行后补充。

## 原生集成检查点

- `swift build`：完整 Saytile App 通过（CLT 27，State 属性包装器兼容）。
- `scripts/build-app.sh debug`：App 打包、Info.plist 校验及 ad-hoc codesign 校验通过。
- 打包 App `--smoke-test --data-directory <独立空库>`：启动、恢复、无权限请求、异步退出通过。首次发现退出死锁后已修复，见 `evidence/native/startup.log`。
- Apple SpeechAnalyzer 中文合成验证：10.616 秒，识别完成，尾句保留；见 `evidence/native-audio-probe.json`。
- 生产 VAD/保存/SQLite 加速负载：2091 秒虚拟输入，180 条独立原音、66.9 MB、全部封段，待识别队列保留；见 `evidence/native-audio-load.log`。非真实 30 分钟收音与能耗结果。
- 原生单测：源码类型检查通过，全量运行尚在处理 CLT Testing 插件/Framework 定位，不计入已通过测试数。

## 原生单测已执行

`scripts/test-native.sh`：**49/49 通过**（Swift Testing，真实 SQLite/文件系统/原生生产函数与隔离输入适配器）。测试含存储 33 项、输入 11 项、音频 5 项。

CLT 测试方案使用默认 Swift Build、临时构建目录及已安装 TestingMacros 插件。没有安装完整 Xcode，没有修改系统设置。首次运行发现父目录符号链接校验漏洞，已以逐层 lstat 修复后复跑全部通过；失败证据 `evidence/native-tests-initial-failure.log` 保留。

原生输入板离屏渲染已完成，`evidence/native/panel-empty.png` 展示实际 SwiftUI 内容，不是 HTML 原型。实际目标应用 AX/SPA 尚未验收。

## 实时管线与实际系统验证

- 5 分钟实时生产 C ring → AVAudioConverter → WebRTC VAD → WAV/SQLite：6,615,000 输入帧，丢帧 0，10 段封存，原音 300.0 秒。wall 300.42s，CPU user+sys 3.14s（约1.05%单核平均）、max RSS 20.4MB。见 `evidence/native-audio-realtime-soak.log`；不包括 ASR、UI 或整机功耗。
- 正式打包 App 的中文合成音频识别通过，见 `evidence/native/app-speech-prepared.log`。首次未准备该 App 资产失败保存在 `app-speech.log`；已增加首次收音后自动准备。
- 硬件计数探针首次触发 Swift 6 MainActor 隔离崩溃；生产与探针 tap 改为 nonisolated 工厂返回 @Sendable 回调，修复后实际采集 49 buffers / 235200 frames，见 `device-probe-fixed.log`。没有读取、保存或识别环境样本；失败摘要保留 `device-probe-initial-failure.json`。
- 后台禁止激活的专用 NSPanel/NSTextView，真实 AX 局部中文/emoji 插入、UTF-16 光标、局部确认、前后文保留及前台 PID 不变通过：`evidence/native-ax-fixture.json`。不等同完整生产绑定/浏览器 SPA 测试。
- 生产 AppModel 的8项隔离检查通过：初始加载、历史不自动入板、明确复用、清板不删档案、当前语音、收藏、搜索及清理预览等待，见 `evidence/native-app-model.log`。
- 输入板（空/有文字）、档案详情、设置已经实际 SwiftUI 离屏渲染核看，见 `evidence/native/*.png`。没有启动外部浏览器。

本轮实机测试发现的问题均先修根因，再复验；没有将初次失败或权限未验证写作通过。

## 发布候选原生测试

最新全量 **69/69 原生测试通过**，6 suites，见 `evidence/native-tests.log`。新增持久草稿跨重启/独删原音/删记录保护、后台音频回调实际执行、首块登记前崩溃恢复等回归。没有用编译成功替代测试执行。

## 最终界面与草稿

`scripts/test-app-model.sh`：**16/16 通过**，包含持久草稿切换/重选、刷新不覆盖、保存时继续输入及退出保留空草稿。脚本曾错误链接旧静态库，现已统一先构建全部产品，失败记录保留在 `native-draft-probe-initial-failure.log`。

`scripts/test-startup-focus.sh`：打包 App 实际启动菜单栏与非激活输入板，3秒观察中前台 PID 不变，正常退出；未访问其他应用内容。实际符号检查修复了不可用的错误状态 SF Symbol，避免故障时菜单栏图标消失。

## 远端兼容修复记录

PR #2 的本机 Swift 6.4 编译与 Release 包验证通过，但远端 Xcode 26.6 / Swift 6.3.3 在 SwiftUI Binding 的 actor 方法引用适配时触发编译器 IRGen 崩溃（SmallVector），未把该 CI 写作通过。失败日志 `evidence/native-ci-compiler-failure.log` 保留；修复将显式闭包替代方法引用，仍运行完整原生测试与 App 构建。

## 最后故障回归

最新 **72/72 原生测试通过**、**16/16 AppModel 检查通过**。新增目录创建失败、实际写入 ENOSPC、末尾同步失败三项生产路径故障注入：记录均封段，无持久原音标缺失；有持久原音只发布此前已确认水位，文字保留。轮转失败不会误用上一文件的水位。5分钟正常管线结果无需因异常清理分支修改重复跑。

## 最终发布包

源码 `4c4430426050553a7df573053ff4cc582e45b3fa`：远端原生CI及设计契约CI全部通过，Swift6.3.3 Binding兼容修复已由实际CI证明。

Release DMG 校验通过；只读挂载中的App严格签名验证及启动通过；已安装到 `~/Applications/Saytile.app`，安装后再次签名和独立库启动通过。`evidence/native/release-manifest.json` 记录最终校验和、来源、验证和边界。同步工作目录会重新附加FinderInfo，使目录中的App副本严格签名失效；已改用校验完好的只读镜像和非同步Applications安装位置交付，没有修改系统安全或同步设置。


## 2026-11-06 · RC 收口启动

重新核对远端 main、PR #1/#2 与两条 CI；当前均一致，发布物仍是 Beta.1。已发现需要工程修复的候选缺陷：锁屏/撤权生命周期、ASR末尾定稿、输入取消及目标变更、draft搜索、并发打开资料库、输入板最新30条静默截断。将在独立合成环境建立复现及回归，不用历史 CI 或原型验证代替。

工作树发现7个未跟踪 ` 2` 副本，保留原状、不提交、不据此推断用户意图。


## RC 第一轮工程检查点

- `evidence/rc/native-checkpoint.log`：109 tests / 14 suites PASS。
- `evidence/rc/app-model.log`：21 checks PASS，含116条当前表达分页和断开设备UID保留。
- `evidence/rc/ui/run.log`：9张生产SwiftUI窗口渲染、5次真实AXPress；仅fixture PID、前台不变。离屏本进程AX树不展开，已改为透明非激活原生窗口+独立AX客户端；前期本地mouse探针仅模式成功，档案点击未通过，没有冒称全控件通过。
- 存储：9项真实进程/升级/写入故障；10万记录30万版本，partial写p95 0.14ms，清理时并发写p95 0.24ms。详细输出见RC-STORAGE-WORK。
- 输入：22单测、9原生后台全链路、WebKit页面变更/能力拒绝、20headless DOM检查。最初WebKit 5/5含延迟通知串扰，经隔离复查发现silentContext失败；根因修复为有界语义身份并重新回归，失败如实保留。详见RC-INPUT-WORK。
- 音频：30分钟墙钟、39,690,000帧零drop，60段1800秒、57.61MB。只包括ring/转换/VAD/WAV/SQLite，不包括真实麦克风、ASR或整机能耗。中文8条两声音实时TTS语料和Apple识别器对照披露错字，详见RC-AUDIO-WORK。

当前是检查点，不是最终RC签字。签名安装升级、最终CI及交叉审查仍在进行。


## RC 最终根因与回归

1. 独立审查复现跨段倒序B→A：现在以创建序号作为绑定起点和最高派发水位；旧段迟到全文/尾部独立deferred，不重放，不阻塞C，删除B也不使水位倒退。
2. 一次118项全套出现4个新时序用例失败（保留native-timestamp-failure.log），专项及两次诊断没有复现。**未将SQLite精度猜测当结论**：4096个Double实测无损。改以同事务rowid区分绑定前后相同时间戳，统一boundAt与Unix时间比较，新增确定性新旧同tick回归；最终122项全部通过（input-full-final.log）。没有新增sleep或放宽旧内容边界。
3. 首轮云端111项native PASS，后续AppModel入口因SwiftPM和SwiftBuild模块目录不同而失败。修复明确静态库产物与两种模块布局，保留ci-layout-failure.log；本地经典SwiftPM与CLT均21checks PASS。
4. 实际打包App在a780aaa检查点待命300.03秒：user2.16s+sys0.43s，平均0.86%单核；maxRSS80.15MB，最终RSS约55.84MB。原始time口径和每5秒样本均保留（app-idle.json/log）。仅空隔离库、菜单栏/刷新，没有麦克风、ASR或整机功耗，不冒称最终发布SHA或72小时。
5. 音频真实AVAudioPlayer另有2项零PCM集成：跨块seek、自然结束、stop/shutdown/租约与删除保文，未采麦或有声外放。

最终发行验收将补充精确源码SHA、DMG散列、只读挂载签名、Beta App→RC App安装升级、正常重启及重复实例拒绝。


## macOS 26 兼容修复 · 最终CI揭示

`8b22e24` 在本机macOS27通过，但云端macOS26.6.2的系统SQLite对REAL→TEXT转换发生舍入，122项套件中精度/时间用例出现69项断言失败。此时才有明确跨版本证据；不能把先前macOS27的4096样本无损结论推广到旧系统。

已将StoreSQLite按SQLITE_FLOAT/INTEGER分别使用sqlite3_column_double/int64读取，再交Swift无损表示，UTF8文本路径保留，测试未放宽。现有6项精度/边界/NUL测试PASS，最终修复head仍必须通过macOS26 CI。原错误见 `evidence/rc/ci-sqlite-precision-failure.log`，本地修复回归见 `storage-real-precision-fix.log`。

## RC1 最终发行验证 · 2026-11-06

- 源码 `8906a9dc4b2ec186f634bb2c829d8eb0c1700679`，sourceDirty=false。[macOS 26 native CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42196920566/job/127822389253) 122 tests / 15 suites、21 AppModel、构建、9图、启动全部 PASS；[设计契约 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42196920610/job/127822388691) PASS。摘录 `evidence/rc/ci-final-summary.log`。这已验证旧系统 SQLite 根因修复，测试未放宽。
- 最终 DMG SHA256：`fb001a8ad0c107570acc6d263e590e49eb5bb9827d617e30c72cbaa4c247ed2a`。只读镜像签名、独立安装、实际 Beta App 打开合成旧库→RC App 升级、三次重启、重复进程拒绝、强制退出恢复共6组 PASS。版本/草稿/固定/不确定派发及原音保留；RC启动0.530秒，三次重启0.161/0.162/0.164秒，仅为当前独立数据样本。
- 最终包生产 SwiftUI 9图与真实 AXPress 5次 PASS，作用域为透明非激活窗口与 fixture PID；输入板、档案筛选和保存实际执行，前台不变。紧凑详情及设置已再次视觉检查；不是 HTML。
- 最终包读取既有自编中文 TTS，ASR completed、error=none，含“请不要自动发送”和末尾“保留原始录音”；标点/数字展示与原文不同，原样输出保留在 `packaged-speech.log`。系统框架输出非致命 sandbox_extension 警告，识别和启动流程实际成功，未隐去日志。没有采集麦克风。
- 最终包启动焦点探针 PASS，退出0、frontmost_unchanged=true。已更新 `~/Applications/Saytile.app` 并保留旧包备份；严格签名和独立库 smoke PASS，未打开正式库、未自动收音。详情 `installed.json`、`installed-smoke.log`。
- 最终二进制/DMG/CI/证据归属集中在 `evidence/rc/release-manifest.json`。30分钟管线与5分钟待命仍准确归属较早工程检查点，没有被改写为最终包72小时验证。

上述通过不覆盖真人发音/噪声、完整用户前台浏览器插入、物理睡眠/锁屏/设备断开/TCC更改、多显示器/Spaces和整机能耗；剩余范围见最终验收文件。无临时用户操作要求。最终独立文案审查另收紧 README 的“检测到页面变化”措辞，不改变代码/安装包，不新增测试计数。

## 最终前台隔离尝试与后台回归

复用原有 NSTextView/WKWebView fixtures，增加可选短批次：真实 `AXInputAccess.frontmostSelection()` 前后仅加 fixture PID guard，不伪造 AX 对象；已有 AX 权限、只读键鼠事件年龄检查、30秒上限、用户操作/切走立即退出且不夺回焦点；日志不输出字段全文。编译、Python语法和diff检查通过。

一次执行在任何激活前以 `NOT_RUN` 退出（`evidence/rc/input-foreground-batch.log`）：空闲条件未满足。随后只读年龄诊断见最近keyDown/keyUp约1.27/1.18秒、鼠标约41秒；未发生的tablet事件年龄为系统uptime，排除检测实现误将它们当零的猜测。没有读取键值/坐标，不能归因事件来源；未重试前台模式。不能将编译或这次安全退出计为实际前台插入通过。

修改后的默认后台路径已重新执行：原生生产协调器+SQLite+真实AX 9项通过；WebKit 6类变化、无语义/截断拒绝与无发送通过，后台写入仍未确认且不重发。证据文件原样更新，不增加逻辑套件计数。生产源码和已验证DMG均未改变。

</details>
