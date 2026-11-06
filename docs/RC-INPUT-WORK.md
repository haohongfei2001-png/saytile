# RC 输入可靠性工作

2026-11-06。负责人：输入子代理。仅隔离合成数据；不访问真实草稿或聊天，不激活测试窗口，不请求新系统权限。

## 已发现的根因

1. `NativeInputCoordinator.perform` 未检查任务取消。取消发生在等待数据库操作期间时，仍可能尝试外部插入。
2. 绑定只在下一次插入前检查当前焦点。应用内部切走再返回原控件、网页复用同一编辑节点的导航生命周期没有观察；URL/标题相同不能证明逻辑页面未改变。
3. 外部确认只等 120ms。慢编辑器可以已收到一次插入，却被过早标记未确认；不能靠重发修复。
4. Beta 测试分为模拟 InputAccess 和真实 AX 原语 fixture，尚未在同一试验贯穿生产协调器、SQLite 账本、真实 AX 适配器及目标文本。

## 验证层次

- 原生协调器逻辑：模拟系统状态、真实独立 SQLite。
- 后台原生集成：禁止激活的专用 NSTextView 应用。测试使用明确 fixture 目标选择器；真实 AX 读取、局部插入、确认、生产协调器及 SQLite 完整运行。不得称为真实用户前台绑定验收。
- 无界面浏览器：独立 localhost/内存合成文档，验证编辑事件、导航、selection 与不发送。不能替代 macOS AX 浏览器验收。
- 生产前台选择器只读取用户明确绑定的当前目标，测试不得将其指向用户现有应用。

## 本轮进度

- 初始代码审查完成；上列问题待修复。
- 原生构建/测试 scratch 固定在 `/tmp/saytile-rc-input`，避免与其他子任务构建互扰。
- 每个证据文件将记录所测层次、实际通过项和未覆盖边界。

## 第一轮实现与结果

- 增加任务取消检查，确保数据库预留等待期间取消后不再尝试外部写入。
- 新增 AX 焦点、窗口、标题、控件销毁、值/选区及网页布局通知观察；旧目标即使切回也不会恢复旧绑定。
- 对上次确认插入的局部尾部进行再次核验；不读取或覆盖整个真实目标字段。
- 对同一外部操作进行最长 560ms 的有界结果确认，最多一次派发，不因确认慢而重发。
- 区分显式单次插入与连续绑定。网页连续模式要求通知观察及局部范围读取能力；网页结构变化停止该绑定，内容继续保留。
- `evidence/rc/input-native-tests.log`：18 项输入测试通过。
- `evidence/rc/input-native-coordinator.log`：8 项后台真实 AX 集成通过，贯穿实际 NativeInputCoordinator、真实 SQLite 账本、真实 AXInputAccess 和独立 NSTextView。
- 全链路后台试验只注入目标选择器，未冒称测试了用户前台 WindowServer 选择或浏览器。
- 待继续：WKWebView 同 URL 复用节点/布局事件、无界面 Chromium DOM、观察器生命周期与真实未确认边界。

Apple API依据：[AX 通知规则](https://developer.apple.com/documentation/applicationservices/axnotificationconstants_h)；[观察器创建](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate)。应用级观察可接收该应用任意控件发出的对应通知；测试只注册独立 fixture PID。

## 第二轮根因修复与最新结果

初次 WKWebView 5/5 表象受到上一轮 restore 的迟到通知影响。加入“绑定后静置并确认仍存活”后，可靠复现同 URL / 同编辑节点 / 同值 / 同光标、仅上下文标题区变化时**没有 AX 布局通知**。失败保存在 `evidence/rc/input-webkit-silent-context-failure.log`，不能把通知注册成功视为通知完整。

已修复：

- 每次写入前重新计算有界网页语义摘要：节点身份、层次、标题、静态语义文字、URL、选中状态。排除目标编辑子树及其他可编辑字段；只在内存保留 SHA256 摘要，不将页面内容写数据库或日志。
- 最多 128 节点、32 KiB 静态语义文字、150 ms 遍历预算。任何截断、不可读或无语义锚点都标记未知，拒绝网页连续绑定，保留用户明确单次插入及复制。
- 全部语义检查之后、真正 AX 写入之前再次查询实际前台/窗口/编辑控件/光标，避免把遍历前的旧焦点用于写入。粘贴回退同时核对剪贴板 changeCount，用户在检查期间的新复制不会被当成本次内容派发。
- 本次插入的值/选区通知只有完全符合预期 UTF-16 追加结果才视为自身变化；用户在确认期间改动选区会使绑定失效。已确认局部尾部之后若范围读取能力消失，也停止追加。

最新证据：

| 层次 | 结果 | 证据 |
| --- | --- | --- |
| 真实协调器 + 隔离 SQLite + 模拟 OS | 22 项通过，含取消、延迟确认、生命周期、局部尾部、确认期间用户改选区、无上下文拒绝 | `evidence/rc/input-native-tests.log` |
| 真实协调器 + 隔离 SQLite + 真实 NSTextView AX | 9 项通过，含中文/emoji UTF-16 增量、重复抑制、真实选区通知、周围内容不变、取消、不激活 | `evidence/rc/input-native-coordinator.log` |
| 真实 WKWebView AX 语义/生命周期 | 6 类变化拒绝通过：同 URL 清空、静默上下文变更、相同语义节点替换、pushState、编辑节点替换、选区。另截断/无语义拒绝、不发送通过 | `evidence/rc/input-webkit-observer.log` |
| Chromium 156 headless DOM + 实际 Swift 协调器/SQLite | textarea / contenteditable 共 20 项通过，覆盖 Unicode、重复/增量、选区、页面变化和不发送 | `evidence/rc/input-browser-dom.log` |

重要边界：后台透明 WKWebView 的 AXSelectedText 返回成功但没有修改 DOM；协调器正确记为 `unverified`，只尝试一次。此测试**没有通过 WebKit 文字插入**，也没有用 DOM 结果替代原生 AX。头部 URL/页面 title、所有可访问语义、节点身份、选区和草稿都完全不可区分的内部路由，没有通用 AX 原子页面身份可验证；该类页面不属于已验证的连续输入支持范围。当前能力检测不能证明任意网站都不存在这种隐藏路由，必须进入 Pro 审查，不能宣称通用网页零错投或将此称为“用户已接受的限制”。

## 可复跑命令

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-rc-input/build SAYTILE_TEST_LOG=evidence/rc/input-native-tests.log bash scripts/test-native.sh --filter Input
python3 scripts/test-input-native.py
# 安装免费 Playwright 依赖至独立临时目录；不创建真实浏览器 profile。
npm install --prefix /tmp/saytile-rc-input/browser-tools playwright --no-audit --no-fund
# 默认使用该版本已安装的 headless engine；可通过 SAYTILE_CHROMIUM_EXECUTABLE 指定已有 headless shell。
node scripts/test-input-browser.mjs
```

`NativeUIControlProbe.swift` 另提供只操作明确 fixture PID 和可选窗口标题的 remote AXPress，用于父线实际 SwiftUI 原生按钮测试。无权限退出 5、不请求权限，不选择当前用户应用，不激活、不发全局事件。此工具本身不代表 UI 流程已通过。

## 父线独立审查

已报告并由父线处理：直接输入只遍历最新 30 条导致旧积压漏派；busy 前记 revision 导致零派发被永久跳过；退出排空音频前应先撤销输入绑定。已查看 8 张真实 NSHostingView 截图；未见重大视觉缺陷，具体建议为搜索无结果文案与最小高度/长错误情况下详情可滚动。输入子任务未修改父线 AppModel、Views 或 AppDelegate。

## a780aaa 发行独立审查与顺序修复

只读检查 `build-app.sh`、`package-beta.sh`、native CI、AppModel 退出/刷新路径、UIReview 与支持边界。脚本 `bash -n` 通过；现有 bundle 的 `otool -L` 只引用系统库，没有遗漏临时构建目录的动态库。构建临时 stage、签名复验、CI 渲染与本机 AX 控制分层没有发现新增发布阻断。未改动未知 ` 2` 副本。

发现并实际复现一项 P1：A 先说但 final 迟到，B 后说先 final；跨两次候选查询会派发成 B→A。真实生产 Store/SQLite 的独立反例见 `evidence/rc/input-order-before-fix.log`，没有操作外部编辑器。

修复由存储代理与输入代理协同完成：同一 binding 的自动输入只沿录音顺序向前；更早段的迟到全文/尾部保留在本地，可明确取用；不在后段末尾插入，也不阻塞后续新段。coordinator 将 `StoreError.lateRecognitionDeferred` 映射为 `.deferred`，保持绑定，不进行 AX 尝试。增加 A/B/C 与 A-prefix/B/A-tail/C 两项真实 Store 协调器回归，使用各 Recording 实际 createdAt；最终 **24 项输入测试通过**。

迟到段若已被候选 SQL 排除，不会触发 coordinator 的 deferred 消息；其界面提示由父线接入，不能只依赖这条结果消息。此前 WebKit 原生插入及完全不可区分隐藏路由的验证边界仍有效，没有因本次顺序修复而改变。

## 全量并发测试发现的时间资格边界

父线首次全量 118 项出现 A/B/C 首段未派发的 4 个期望失败，原失败日志保留。加入实际 result 与 decoded/binding 时间差诊断后，显式 Date 和恢复原 default 参数调用的两次全量分别 118/120 通过；没有获得原失败的具体时间差，不能将偶然通过当作根因解释。

已排除“当前 SQLite 文本转换只能保留 15 位导致读回丢精度”的假设：使用 a780aaa 原数据库适配器的微秒样本往返均为零差，见 `input-time-precision-diagnostic.log`；存储代理另验证 4096 个连续 Double 值。Foundation 原生 reference-date 与 Unix-epoch Double 可有小于一微秒的转换差异。

确认并修复的资格边界缺陷是：运行时在数据库建立绑定之后另取一次更晚时间，再以 Date 的 `<=` 排除记录，不能正确表达同一时钟刻度中的先后创建关系。现在绑定开始时的同一个 Date 同时传入 Store 与 InputBindingInfo；运行时仅按相同 Unix 精度作 `<` 预筛，数据库事务捕获录音 rowid 起点，排除绑定前旧记录并允许同时间戳的新记录。跨段顺序也改为实际创建 rowid，不依赖 UUID 字典序。

新增确定性协调器测试，实际持久化 Recording.createdAt 与绑定时间完全相等，仍按新 row 资格成功输入；没有增加 sleep 或伪造调用方 startedAt。最终 **122 项全量测试通过，含 25 项输入测试**，见 `evidence/rc/input-full-final.log`。此前 WebKit/前台覆盖边界仍未改变。

## macOS 26 最终兼容结论

上文“当前 SQLite 无损”只针对本机 macOS27，不能泛化。云端macOS26随后实际复现REAL转TEXT舍入；`8906a9d`改为typed double/int64读取，测试不变，最终122项/21 AppModel全部通过。具体失败及修复证据见 `V1-TEST-RESULTS.md`。

## 可选真实前台批次（未运行成功）

已复用现有fixtures增加 `SAYTILE_ALLOW_FOREGROUND_INPUT_FIXTURES=1 python3 scripts/test-input-native.py --foreground-batch`，仅明确执行时才允许短暂前台模式；实际解析器前后校验fixture PID，既有权限且空闲至少60秒，否则不激活。30秒硬上限，任何会话输入或外部焦点变化退出且不夺回；正常完成需核对恢复PID，日志不保存字段全文。

本轮唯一一次尝试在激活前因空闲条件未满足退出，故结果是 **NOT_RUN**。已只读确认近期事件年龄，未读键值/坐标、未重试或归因其来源。默认后台模式重新通过9项原生AX和WebKit观察/拒绝检查。此补测没有扩大前台浏览器支持声明。
