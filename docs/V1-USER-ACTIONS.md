## 2026-11-16 · 隔离确认框宿主修复

499签名本机验收在确认框弹出后被前台保护拒绝，未执行该次确认，不交付该包。独立原生probe复现系统确认框另建可聚焦窗口、单次操作成功却返回-25205，并验证accessory→prohibited的实际策略切换后真实AX确认仍可用。仅反馈验收宿主改为禁止激活并断言实际策略；产品行为、普通控件和焦点保护均不变。正常/正反故障共13项最终签名验收及新源码CI待完成。现用0.18与用户资料保持。

## 2026-11-16 · 反馈交付边界

CI测试差异由工程处理，不需要用户点击、录音或提供日志。当前0.18（492）及正式App保持。尚待已有Cloudflare账户的一次Wrangler登录，之后才能迁移/部署既有私有反馈服务并验证Saytile真实送达；不需要新账户、付费服务或在聊天中提供密钥。原生隔离测试使用注入传输，不能当作已上线。

## 2026-11-15 · Release兼容性根因修复

无需用户处理编译器问题：已自行定位并修复；现用0.18仍保持。Riftlet PR104最终五项CI通过，但Cloudflare部署身份仍是唯一外部授权阻断，真实反馈入库尚未运行。

## 2026-11-15 · 反馈闭环与部署边界

唯一外部阻断：现有Cloudflare账户尚未有本机/CI部署会话，需要账户持有人完成一次Wrangler登录。无需新账户、付费计划或在聊天粘贴密钥。登录后工程可继续原D1迁移、服务部署和一条隔离反馈的真实入库验证。当前0.18及正式App/资料保持，不要求用户测试或提供日志。

## 2026-11-15 · 同一0.19版本接入用户反馈

继承PR46源码fe5da285的外观预设（该SHA五项CI已通过，542项Swift Testing与188项AppModel）。在持久隔离分支codex/product-feedback添加设置内用户反馈，复用Riftlet的独立SQLite发件箱、Keychain capability、确定收据和重试/撤回保护；只发送用户主动填写内容，固定product=saytile。默认不读取录音/转写/日志。共享服务需兼容新增产品字段及私有仓库分类；真实联通、最终签名包和新SHA CI尚在执行，不宣称已接通或已安装。现用0.18与正式App保持不变。

## 2026-11-15 · 外观修复进行中

无需用户操作。字体顶端定位已通过定向回归；真实候选复验与完整CI完成后再更新同一安装入口。本轮不测合盖麦克风，不调用云服务。

## 2026-11-15 · 外观设置

工程验收使用隔离合成资料，不需要用户朗读、授权云服务或提供日志。Mac继续合盖，麦克风不测。默认保留当前外观；颜色与玻璃档位的个人喜好由用户以后正常使用时选择。此次不公证、不更新官网内测包、不触碰正式App或用户原音。

## 2026-11-15 · 0.18 应用内更新（实现中）

以已安装0.17（488）/PR43源码58bc8f96为基线，在codex/in-app-updates独立分支接入Sparkle2.10.1。已核对Riftlet最新远端实现，复用单更新器、设置/菜单统一状态、后台轻提示和用户确认安装；不改主语音板。修复当前mandarin候选被排除、安装包缺少更新配置的问题。正式与候选分别绑定签名更新源，禁止自动下载安装和系统信息上报；旧草稿安全保存流程改用macOS terminateLater/reply，后续通过实际重启验收验证。

PASS：带Sparkle原生编译、18项打包配置测试。待执行：最终Swift/CI、原生检查/下载/验签/安装/重启、升级资料回退和本机安装。空更新源不包含安装包或发行条目；未发布版本。真实麦克风、ASR质量、云端付费调用不在此轮。

## 2026-11-14 · 原生档案验收窗口稳定性

e4407fd3 本机签名包的3次真实段落复制按钮、档案菜单、编辑和收藏通过；整段静音回听后的停止按钮查询得到0个AX节点而失败。该原生验收窗口仍采用alpha=0，命中已有UIReview注明的系统AX窗口消失条件。只把档案验收窗口改为既有timeline前缀：非激活、不能key/main、放到全部显示器之外但保持drawable。未改产品窗口或回听逻辑，没有重试按钮，也没有放宽断言。当前候选484仍未更新；前一SHA的远端CI保留并等待自然完成，新源码将单独复验。

## 2026-11-14 · 段落复制最终 CI 跟进

8ffa4461 的本机最终签名段落/AX/菜单/编辑/回听及 484→486→484→486 回退通过；525 项 Swift Testing 和183项 AppModel 同源CI通过。完整CI为3/5，未安装：Chrome最后目标切换场景在绑定准备阶段targetChanged，未发生该场景写入；打包依赖准备exit141使后续9步未运行。原日志不足以定位二者的具体子条件。三组固定版本git归档管道各3次本机均0/0，不能把管道猜测宣称根因。

本次仅补测试/构建失败的脱敏原因输出，不改生产输入判定、ASR、重试次数或期限：AX保持同一绑定与相同读取次数，失败前记录布尔差异；构建记录脚本行号/返回码/管道返回码，注入141确认保持原失败退出。将用下一源码一次完整CI取得缺失证据，再决定修复；不把重跑成功冒称已根治未知原因。现用484、正式App和用户数据保持。

## 2026-11-14 · 0.17 自然段复制

本轮不需要用户测试。保持合盖，不测麦克风、不访问用户档案或剪贴板。沿用已验证识别运行库，只改变复制范围；完整原生按钮、签名包、升级回退与 CI 通过后才更新现有候选路径。不合并 main、不公证、不公开发布。 [规则及验证](PARAGRAPH-COPY.md)。

## 2026-11-14 · 0.15 自然段整合

0.15（483）的完整Swift套件523/523已通过；前台Chrome首插入一次写入正确，但紧接着AX选区/焦点快照暂不可读，使原有确认窗提前失效。已将这一首次不可读事件接入既有有界只读核验，仍需两次完整同目标、光标及全文证据；二次变更直接失效，不重发、不夺焦点、不放宽安全条件。32项输入测试（62个参数用例，含新增16个故障场景）及独立真实AppKit/WKWebView、9项owned-range通过；最终SHA前台CI待完成，候选478未更新。详见 evidence/natural-paragraphs/web-first-observation/。

后续783921b原始wire证据确认连接检查相对休眠累积漂移：6.272秒音频在12秒上限前未送完最后2306字节/EOS。已改为累计PCM时长的绝对单调时钟，保持超时、完整性断言和麦克风识别路径不变；同音频13/13协议回归、52场景零违规。最终同源CI待运行，不继续盲目重跑。

0.15（481）首次CI在已有协议normal检查超时，本机及一次受控CI复验通过；复验另发现播放器0.9下界的1 ULP浮点误判，已由真实AVAudioPlayer轨迹复现。仅修测试数值比较、隔离时间敏感播放器套件并保留协议wire证据；产品逻辑未改。全部测试保留，待新源码CI和签名同源复验。

最终CI首轮（4622f48）：523/523 Swift Testing、172/172 AppModel及自然段原生步骤通过；唯一失败是旧12,000条午夜断言仍要求零分隔，而该午夜记录对实际间隔224秒（普通夹具间隔24秒）。现仅修验收断言为单一自然段换行、原文不变、无时间标题；产品规则未改，候选478仍保持，待新SHA同源12k与完整CI。

本轮无需用户操作。Mac按要求继续合盖，物理麦克风NOT_RUN；未运行ASR质量重评（识别模型/运行库未变）。不调用云端或收费API，不更改安全设置，不修改main、正式App及其他任务。候选将在完整验证后沿原有路径更新。 详见[NATURAL-PARAGRAPHS](NATURAL-PARAGRAPHS.md)。

## 2026-11-14 · 0.14 窗口共存候选（原生收口，待签名包与 CI）

基于已安装 0.13（476）产品源码 `0fbca1d892bbc8aa550c4439b8cfcb045af825ae`，独立分支 `codex/panel-window-boundary`。新增设置中的浮板/实体边界，默认浮板；AX 只读窗口几何/控件角色，不读取文档、标题或输入内容。边界调整只作用于普通可移动窗口；全屏窗口不改，改用更遮挡的原毛玻璃及有限平移避让。未改识别、SQLite、录音、已有资料或其他项目。

- PASS：原生 Swift 编译；167 项 AppModel 检查及真实 VoicePanel 鼠标事件/持久化回归；14 组几何测试函数的 881 条纯 Swift 断言（完整 Swift Testing 待 CI）。28 项真实隔离 AX/原生窗口检查 PASS，含控制器实际移开全屏按钮并恢复；4 项材质组合 PASS。详见 evidence/panel-boundary/。
- NOT_RUN：新包安装、最终 CI；签名安装与交付收据将在同源独立证据分支补齐，本阶段不冒称正式发行。
- 麦克风保持 NOT_RUN（用户要求合盖不测）；不运行云端或收费调用。
- 当前安装476保持原状。下一步：最终 SHA 的完整 CI、签名候选、合成资料升级回退和一次原位更新。

## 0.13 · 中文预览稳定性（466）

按用户要求保持 Mac 合盖。本轮测试使用公开录音。内置麦克风、个人口音和现场讲话为 NOT_RUN。 [本轮机器验收](../evidence/mandarin-preview-20261114/DELIVERY.md)

## 0.13 · 连续讲话更新（442）

按用户选择保持合盖。最终候选已打开并核对真实内置 UID、48 kHz 单声道；20 次电平全为 −120 dBFS。开盖声学回放及用户口音质量未验，不要求朗读或排查。 [同一设备对照与证据](../evidence/mandarin-cadence-20261114/README.md)

## 内测 0.13 中文识别独立候选

本机已安装并启动「Saytile 中文识别候选.app」，可直接点击浮板语音键。0.6B 模型已完成校验；首次收音时如有 macOS 麦克风提示，按系统提示允许即可。本次原速评测使用公开人声和隔离档案。本人自然语音与口音仍待个人体验。

## 当前：Saytile 内测 0.12

单击菜单栏的 tile 打开菜单。选「收起语音板」可隐藏浮窗，再选「展开语音板」会回到原位置和大小。窄板上右击语音键，选择「恢复阅读尺寸」可以一次恢复阅读大小。

## 内测 0.11

打开「语音档案与设置…」，点击档案正文就能修改。右上紫色星标筛选收藏；移到原文上或用键盘聚焦，可回听或收藏该段。默认连续安静两分钟才开始新的时间组。

## 内测 0.10

横拖调宽、竖拖调高，也可以拖角同时调整两者。语音键在右下方；窄板上方仍是板面。需要原阅读尺寸时，点菜单栏里的「展开语音板」。

## 内测 0.9

- 点最小语音板可开始或暂停；按住板面拖动可移位。左右边缘都能拉开。
- 要直接恢复原来大小，点菜单栏图标，选「展开语音板」。已经缩小后退出或从旧版更新也可用。「收起语音板」仍表示隐藏窗口。
- 不需要重新配置设备、模型或档案。

## 内测 0.8

本轮不需要重新选择模型、授权或整理档案。录音没有转写时会从批量清理中排除；仍可从档案回听或重新识别。

## 内测 0.7

在菜单栏选「语音档案与设置…」。点每条记录旁的星标即可收藏或取消；点语音档案右上角的星标，只看已收藏的记录，再点一次回到列表。

## 内测 0.6

打开原来的 Saytile.app。语音板右侧按钮负责开始和暂停；需要检查权限或设备时打开「设置 → 麦克风」。在「本地模型」列表直接选用模型；只有主动使用在线识别才需要进入「云端服务」配置和授权。本次更新无需重新登录或迁移资料。

## 内测 0.5

单击菜单栏图标展开菜单，在里面选「收起语音板」或「显示语音板」。左右拉边调整每行容纳的字数，上下拉边调整可见行数；缩到最小时只剩语音键，拉宽即可恢复。本次更新无需重新配置识别或授权。

## 内测 0.4

继续打开同一个 Saytile.app 即可。上下滚动阅读，停下时留在当前文字；不必更改系统滚动设置。讲话会接在当前正文后，向上滚动可回看，按回车可自行换行。

在「设置 → 输入与快捷键 → 输入板」可切换「显示边框」，默认开启，选择会保留到下次启动。直接打开现有的 Saytile.app；点正文输入或选择文字，使用 macOS 常用剪切、复制、粘贴与撤销快捷键。无需安装第二份应用或迁移档案。早期候选安装说明仅作为历史留存。

## V1 原生产品界面

工程验证使用隔离资料。最终设计候选供直接打开与审定。 [设计记录](V1-NATIVE-PRODUCT-DESIGN.md)

## PR #18 前台输入

此轮仅使用独立草稿、进程和临时 SQLite。无需重装、提供日志或在私人对话中试输入。 [验收记录](V1-FOREGROUND-RELIABILITY.md)

## V1 夜间体验候选

工程使用隔离档案。自然讲话、听感和真实使用体验留待正常使用时判断。个人体验保留已选内置输入。外部网站的访客访问验证由工程记录，无需登录排错。本机 Apple 中文识别可直接体验。已有 Qwen 部分下载可以继续或删除。直接打开既有个人体验入口；在 macOS 已识别为开盖时可用内置麦克风判断自然讲话。以上编译与控件问题由工程复核，无需用户操作。 [本轮记录](V1-NIGHTLY-EXPERIENCE.md)

## MacBook 内置麦克风 · 个人体验修复

原音、文字和编辑均保留；仍只需在系统识别为开盖后正常使用，不需要运行诊断。

本轮不需要提供录音或诊断。系统实际识别为开盖、内置麦克风有信号时，正常说话即可判断实时体验。 见[验收范围](V1-BUILTIN-MIC.md)。

## V1 统一发行候选

工程验收无需用户录音、排错或收集日志。当前候选等待集中体验，正式分发、公证、线上收费以及真实云端仍在之后的阶段。 [本次完整交付](V1-INTEGRATED-CANDIDATE.md)

## M5 本地中文实时识别候选 .6

本轮无需用户提供 API、录音或排查。公开分发的公证、真实 8 GB 与离电验收由发行和工程人员负责。Zipformer 商用权重权利待上游明确前，保持研究用途。 [评测与交付报告](V1-MANDARIN-LOCAL-ASR.md)

## RC2 连续时间轴整合候选

本轮工程复核无需用户录音或操作。云端联调仅在专用凭据、上传与计费授权就绪后由联调负责人执行。[整合及发布边界](V1-RC2-TIMELINE-INTEGRATION.md)

# 连续时间轴独立预览

没有需要用户参与的开发测试。无选区复制范围暂按最新活动组。未来进入真实云端验收时，由授权人一次配置所选 ASR 与 OpenAI 凭据和上传／费用授权。公证由发行方处理。 [完整交付及验收](V1-CONTINUOUS-TIMELINE.md)

# no-api.10 授权事项

目前没有需要用户执行的开发测试。

- **标准安装分发**由发行方完成。App 和 DMG 已使用 Developer ID 签名。发行方需为 Saytile 配置有权提交 Apple 公证的身份，提交冻结镜像、装订回执并复查带下载隔离属性的 Gatekeeper，再发布新散列。
- **真实云端接入**由账户所有者在原生设置中完成。选择讲话语言，在「AI 识别 → 连接识别服务」中保存所选 ASR 与 OpenAI 两把凭据。中文 Qwen 还需要账户对应地域及 Workspace。分别同意语音或候选文字的处理，并确认内置合成样本的上传和费用范围。密钥仅填入 App 的安全字段。
- **真实质量验收**使用得到授权的既有人声音频。服务接通后再测识别误差和确认延迟。

[原生接入步骤与调用上限](V1-RC2-CONNECTION-SETUP.md) · [机器验收](V1-NO-API-DELIVERY.md)


2026-11-10 · Saytile Cloud: Supabase selected organization quoted USD 10/month. Free-only creation blocked. No merchant/provider calls approved.

2026-11-10 · Saytile Cloud: Vercel authorization succeeded; no further CLI login needed. Secure project settings and the free-only database blocker are recorded in cloud/README.md.

2026-11-10 · No customer action for the ongoing isolated authentication, packaging and upgrade rehearsals.

2026-11-10 · No customer testing or real audio needed for these fixes; the free hosted database allocation remains the external prerequisite.

2026-11-10 · Vercel ingress and native consent retests are handled by engineering. No approval needed.

2026-11-10 · No changes to user actions. Gateway can remain live with model calls disabled while waiting for free Supabase capacity.

2026-11-10 · No engineering test or recording required from the user. Approved organization must have a zero-increment independent slot before remote Supabase creation. Then owner enters secrets once in the named Vercel project and approves a bounded real usage test. Merchant and notarization authorizations are separate release gates.

本机实时识别的工程验收使用固定许可样本，不需要用户录音或提供密钥。模型按需下载，Apple 语言资源由系统管理。

Apple 中文资源已在本机准备，七路样本均由工程自行运行。实际面板、下载器和归档验证不使用私人麦克风。

本机录音的 GPT-6 文字核对需要用户自带 OpenAI 凭据并显式开启独立文字授权。开发验收使用离线回归替身，真实付费调用未运行。

隔离的主板验收使用公开语料驱动原生音频缓冲，无需麦克风授权。

该预览停滞由工程使用固定真人语料复现并复验，不需要用户协助。

工程录像仅捕获隔离窗口。无需个人录音、桌面授权或操作；公开安装仍待发行方 Apple 公证。

本轮无需用户操作。下载、出字、模型切换、原音失败保护、升级及隔离录屏已由工程处理。仅将发行方 Apple 公证、未来真实云端凭据/费用授权和可选真人物理麦克风体验保留为独立事项。

普通话收口：继承 PR #15，Zipformer 仅开放工程评测，模型权重商用许可未获证实。独立工件与 300+ 语料测量进行中，无需用户授权、录音或付费服务。

PR #16 local inference uses public licensed fixtures and isolated temporary archives. No user recordings, cloud credentials or manual testing are required for this comparison. Shipping the Zipformer Large weights requires a verifiable license from the rights holder.

The cold-start memory regression and historical-selection check are being verified on isolated engineering fixtures. No user testing is required.

No action is needed for local engineering acceptance. Apple notarization, evidence on a physical 8 GB machine, and commercial rights to Zipformer Large remain separate from local inference. Cloud credential testing remains NOT_RUN for this work.

Cold model download failures are being checked from independent public macOS infrastructure. This requires neither consumer API keys nor any personal voice data.

For this design candidate no personal speech, account, API key or developer tests are requested. Only the new window design and density need aesthetic review.

The new design experience owns a separate mic permission identity and asks only on a user-initiated start. Do not transfer, reset or change build 269's grants. The visual review uses controlled permission states and an independent, nonactivating window.

No display reconfiguration or testing is requested from the user. The design profile is separate and saved positions are never reset to repair startup.

No user-assisted display movement is needed. The two-screen check uses only the newly created design candidate; its test gesture returns to a natural position for handoff.

唯一体验入口是 ~/Applications/Saytile 设计体验.app。初始保持暂停，用户主动开启时可能出现新身份的系统麦克风提示。没有需要代替开发者执行的测试。仅请审定设置与档案的密度，以及真实桌面上的玻璃质感。未公证，不建议转发下载包给其他人。
