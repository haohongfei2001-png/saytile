# 1.0.0（572）实测验收

产品源码 `42d8e98eaf04a56d34a36cc1aca2aff7061150f4`，签名 App 的 SourceDirty=false。后续文档/测试夹具提交不改生产源。现已正式发布v1.0.0（572），Release及官网真实下载通过；最终结论见末尾。下文阶段性FAIL/NOT_RUN按原始时点保留，不能将后续复核成功改写为从未失败。

## 准确率与连续显示

同一个 M5、同一固定原音，571 与 572 原速交错，共32次原生 App 观察；没有私人录音。证据 `evidence/release-100/paired16/`、`native-comparison-including-failure.json`。

| 项目 | 571 | 572 |
|---|---:|---:|
| 15段最终CER | 46/568，8.10% | 46/568，8.10% |
| 首次有效可见文字 P50/P95，包含录完后才出字的失败 | 1.280 / 2.106s | 1.378 / 5.451s |
| 15段可见新字间隔 P50/P95 | 0.330 / 0.992s | 0.295 / 1.058s |
| EOS P50/P95 | 0.384 / 1.010s | 0.428 / 1.571s |
| App+worker CPU秒 | 79.14 | 76.84 |
| 同时内存footprint峰值 | 1266MiB | 1367MiB |
| 15段ABA | 0 | 0 |

不宣称首字严格改善或显著节能。原测有一段4.2s短句第一次解码耗时4.231s，首次显示5.451s，录完前更新断言 **FAIL**。它慢在worker而非UI；原始日志不删。后续同样本三对原速复核全通过，572首显1.177/1.211/1.270s，571为1.457/1.227/1.093s。仅证明该异常在这三对未复现，不等于根因已消除；首轮统计不被替换。首次加载与共享硬件竞争仍可能有明显等待。

38.8s长句的首字1.833→1.593s，新字间隔P95 1.258→1.099s；最长内部间隔572仍2.203s，未达到永远小于2s。长句ABA两版均3次；当前真实原速对照没有证明ABA数量下降。相同原始候选的离线Swift重放19份ABA11→7，是发布策略局部效果，不能替代真实原速结果。最多等待一条的保护不冻结全段，最终仍是完整原始候选。

16对最终文字和状态逐项一致；两版各16个窗口最终与档案一致，当前5077条AppKit观测无编辑/选区/可见性阻挡。旧PR #54的一次观测提前停止无法追溯确切原因，原失败仍保留；本轮移除AX等待对面板刷新阻塞和全历史反复着色，没有伪称证明旧失败唯一根因。

完整440条独立重跑：原始420段910/10663=8.53%；派生20段65/764=8.51%，不混合分母。440条文字和状态与571逐项一致。五个原有空定稿子段仍failed可重试，原音保留；#52逐帧匹配与独立诊断认为很可能是参考正文外非语音触发，但没有绝对无人声证明，不改为completed或删样本。

## 直接输入与资料

- PASS：38.8s真实模型、正式CaptureWorker/VAD/PCMJournal/Store→真实隔离AX目标，EOS前11次写入，第一笔5.831s，两个子段完成，最终与档案一致，前后文保留，零发送/键盘事件/抢焦点。不是用户现场麦克风。
- PASS：同公开候选原时序重放8次早期写入。单元回归覆盖反向候选撤销证据、手工稿优先、EOS所属范围修正和目标失效。
- PASS：0.18→1.0→0.18→1.0、533→1.0→533→1.0；每组2条合成记录/全部版本/手工稿/PCM校验/自然段/缓存保持；独立空目录启动。实际用户App与资料未变。
- PASS：18项实际CLI隔离检查；所有生产路径在构造Store前拒绝。
- CI首轮缺失冻结测试配置与睡眠夹具已补回精确原件，未删测试。42d8 foreground在WKWebView变短修正后的页面上下文150ms预算耗尽，安全返回correctionPending；前后文未受损。保留完整日志，未增加重试、抢焦点或放宽判定。后续最终CI结果另附。
- PASS：904.830秒原速连续运行，1758次显示变化、44/44记录完成、80原音块、814.050秒VAD选中原音完整对应输入；静音35秒后worker释放、继续讲话后恢复。App/worker峰值RSS 98.05/789.42MiB，后5分钟中位RSS没有增长；该RSS与短语料footprint是不同指标。真实麦克风（Mac继续合盖）NOT_RUN；8GB实体Mac、付费云端、iCloud NOT_RUN。

## 分发与网站

签名App与DMG均Developer ID+安全时间戳验证通过；DMG为同一个实测签名App原样封装。安装身份及更新公钥与公开0.18、现有533相同。

没有找到已配置的notary profile，只查元数据，不读密钥。App/DMG Gatekeeper均 **rejected / Unnotarized Developer ID**。依本轮明确授权允许签名发行并披露系统单App“仍要打开”；不关闭Gatekeeper、不移除quarantine，不宣称公证成功。

网站维持全部15文件设计体系，下载及FAQ更新；本地headless25项通过，7档宽度、编辑/搜索/收藏/实际TTS播放与暂停/拖动/版本/弹窗，零JS和资源错误。第一轮临时HTTP服务器没有正确提供音频Range，拖动失败；补齐服务器Range后原断言通过，正式页面JS/CSS没有修改。线上部署及完整下载尚待实际完成，不能用本地结果替代。

## 最终包安装与完整测试数量

`install-dmg.json`：只读挂载正式DMG、独立Applications复制、五项实际二进制/配置摘要逐项相等，离线空目录启动通过；故意损坏副本资源被codesign拒绝，未绕过Gatekeeper。

42d8完整Xcode运行实际为579项Swift Testing（4+13+12+1+9+8+532个互斥分组）和30项XCTest，零失败；仅引用最后一组532会漏计前面47项。所有原PR54测试文件保留；本轮新增断言，未跳过测试。后续文档/夹具HEAD的CI另列，不能把旧SHA日志当作新SHA运行。

## 显示保护及WKWebView后续诊断

最终VoiceUI原样重放旧失败的14条publications，在following/reading/selection/editing/hidden/controlOnly六种模式、180/260/360宽度共18种组合，252项观察全部通过，18项最终与档案相等。没有用户输入或焦点变化；不能据此声称找到了旧观测停更唯一根因。

2fcff81 foreground第二次失败发生在首次写入前；同一WKWebView窗口与光标仍匹配，但AX的editable观察变化，日志同时出现NSSpellServer超时。产品正确拒绝该不完整状态，未写入。TextEdit、Chrome、Edge、Safari和Chrome焦点读取超时的其余真实路径通过。第一项合成textarea关闭spellcheck/autocorrect的尝试在7de2390仍然失败，已撤回并保留日志。第二项4e39f0b只在测试窗口创建前调用系统拼写服务一次，把服务准备提前到夹具初始化；所有权、光标、文字、窗口断言以及10秒准备/5秒就绪/150ms AX预算均不变，生产输入代码未改。结果尚待实际CI，不能预先归因为唯一原因。

## 最终签名App的实际控件

本机隔离 --controls 原生验收PASS：56次AXPress、9次菜单选择、2项私有剪贴板复制、1项内联编辑、暂停恢复确认与星标重启保留，原生键盘隔离全部通过。仅操作测试App自己的窗口，不激活用户窗口、不读写系统剪贴板、不打开真实麦克风；收音状态变化用注入捕获回执，不能视为现场设备实测。生产源码/二进制均对应42d8，见native-controls/manifest.json。

CI中Native UI的render-only截图与这份本机controls验收分别记录，不能把0次AXPress的渲染检查当作按钮实测。原生档案和设置截图已实际查看；显示、行文、两按钮与统一设置布局保留原设计。

## 4e39 最终生产等价回归

完整原生native、579项Swift Testing/30项XCTest、native-gateway、gateway、design通过。native-brand准确检出两处历史报告清单摘要误差，修正见后续提交，生产资源未变。foreground因GitHub macOS ARM执行器容量不足被取消，未运行任何步骤；单独标NOT_RUN并保留GitHub原始注释。第二项WK假设在此轮尚无测试结果，不把排队取消算通过或当成产品故障。

## 本机最终前台验收（e988117）

GitHub ARM执行器容量不足时，在本机执行同一foreground夹具，使用现有AX权限且确认键鼠已空闲3907秒；只激活自有一次性AppKit/WKWebView窗口，结束后核实恢复原前台PID，未读取其内容。10组检查全部通过，WK首次写入、追加、UTF-16前后保护、变长/变短修正、用户修改、失焦、重启、静默页面变化、预留后AX阻断，以及原生取消/忽略写入/窗口切换均保持安全，零发送。日志与准确测试SHA见local-foreground/receipt.json。系统拼写准备15ms；此单次通过不证明历史CI超时的唯一原因。真实第三方浏览器另由CI已执行路径记录，不能用自有WK代替。

## 最后一次远端前台作业的逐目标结果

e988117：WK/AppKit 10组全通过，TextEdit、Chrome、Chrome焦点读取超时、Edge全部通过；Safari首次写入AX超时150ms，实际一次写入且文本正确，随后快照间歇unsupported，绑定失效，返回unverified；自动确认断言FAIL。没有错投、重放或发送。完整作业与分目标原件见ci/e988-foreground/。这是实际发生的兼容性边界，不能把安全拒绝算作自动输入全通过；保留保护、可复制、原音和文字保留，不改生产超时或断言。仅安排一个有界作业复核，成功也不会覆盖原失败。

## 最终e988117回归与发行裁决

最终测试HEAD `e988117c0a63b47b4d9f8467c6d7d5a41e9a375d`：native、swift-tests、foreground、native-brand、native-gateway、gateway、data-and-prototype共七项SUCCESS。完整Swift Testing579项、XCTest30项、0失败；完整native流程、AppModel220项及Feedback14项通过。与签名产品42d8的193个生产文件摘要相同。

同一HEAD的foreground作业第二次执行，AppKit/WKWebView、TextEdit、Chrome、Edge、Safari均通过；没有产品变更、预算增大、断言放宽或未确认投递重放。首轮Safari的AX超时仍是FAIL，日志保存在ci/e988-foreground/；复核PASS在ci/e988-foreground-rerun/；最终检查总表ci/final-checks.json。虚拟Mac物理睡眠仍BLOCKED，不以其电源预检通过宣称实机睡眠成功。

发行裁决为**按已披露限制正式分发1.0.0**。正常原速与长时间运行、准确率、资料安全及所有权保护达到本轮放行条件；仍不承诺所有硬件调度下两秒出字、零临时回改或所有网页均支持自动输入。一次5.451秒首显和Safari超时属于保留的实际失败，复核没有证明它们永不再现。无已复现的数据丢失、错投、重复输入或自动发送缺陷。

## 正式发行与线上验收

PR #55已合并，main发行提交 `0aa5efd4f8c14e5fe2bb6279968cdd8f6aee3553`；[v1.0.0](https://github.com/haohongfei2001-png/saytile/releases/tag/v1.0.0)为正式非草稿、非预发行Release，保留旧版本。实际包源码仍是42d8，不把合并/收据提交伪称重新构建源码。

[Pages部署45222069957](https://github.com/haohongfei2001-png/saytile/actions/runs/45222069957)成功。真实saytile.com在线25项交互、15个运行文件摘要全部通过；通过页面按钮实际下载完整65,662,466字节DMG，SHA-256 `60e4abf60618d510c7f99d8e92a6ec456f16840f22cc0fcd7eb74ac729c9dba2`，与签名实测包、GitHub资产相同。390/1440线上截图已查看，原有视觉和功能保持。

官网、README、安装说明和Release Notes一致披露未公证。没有可用notary profile，不读取密钥；不等待额外账户操作，按本轮明确授权正式分发签名包。首次Gatekeeper阻止需用户系统单App确认，不能把完整下载PASS当成Gatekeeper自动放行。自动Sparkle更新未推广，本次使用官网/Release手动下载。

当前533仅验证Bundle元数据和可执行文件摘要，仍原样保留；没有读取生产资料。机器总收据publication/receipt.json，以及release.json、pages.json、public-assets.json、public-download.json已提交。物理麦克风、8GB实体机、云端与iCloud仍NOT_RUN，不列作已通过。
