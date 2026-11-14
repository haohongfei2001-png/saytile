# Saytile 0.15（484）自然段交付

产品源码：`ab8545507c79640ec3f419e33467a0263c154844`。Draft PR [#41](https://github.com/haohongfei2001-png/saytile/pull/41) 以 PR #40 为增量基线；本证据分支只更新收据和状态，不改产品源码及已签名包。

## 已安装与使用变化

已原子更新并启动原入口 `/Users/hhf/Applications/Saytile 中文识别候选.app`。478正常退出，484完成启动（PID见activation.json）。正式 `Saytile.app` 0.12（373）保持原签名、源码与可执行文件哈希，用户档案、原音、模型缓存和Keychain未被工程工具读取、替换或清理。[实际安装收据](activation.json)

短停顿继续同一自然段；达到15秒后下一次讲话开始新段，默认60秒才开始新时间组。主板和档案共享段落，档案按整段编辑、回听、收藏。静音本身不插入空行或抢滚动。普通改字、明确删除自动段界与撤销各自保留。

15秒按持久化VAD活动结束/下次开始计算，不使用ASR返回时间。既有1.5秒静音结束等待已经扣除；仍包含VAD hangover与20ms帧精度，不声称精确到声学发声末点。既有历史时间组ID保留。主schema仍6，增加独立自然段sidecar v2；录音ID、原音与文字版本不合并或删除。旧默认120秒变60秒，既有至少60秒的其他自定义间隔保留。

修复编辑冲突丢字、复制取得未显示修订、全部原音损坏时没有失败提示、旧异步成员页闪回。识别模型、运行库及默认配置保持478；本轮未重评ASR准确率/速度，不宣称新的识别提升。

## 最终源码验证

| 项目 | 结果与范围 |
| --- | --- |
| 完整GitHub CI | PASS，5/5 jobs；524/524 Swift Testing声明，172项AppModel检查 |
| 实际前台输入 | PASS，隔离AppKit、WKWebView、TextEdit、Chrome；首次插入/追加、防重复、用户修改/目标变化、取消及零自动发送 |
| 签名包自然段 | PASS，17/17；4份合成原音→3自然段/2时间组，6个独立AX控件检查、3次实际收藏/播放/停止 |
| 签名包历史时间轴 | PASS，12000条，64条驻留，60秒静置、历史滚动/选区、午夜自然换行、实际AX复制和重开 |
| 签名包升级回退 | PASS，478→484→478→484；9张既有表、2条录音/2份原音、4份修订、2草稿、2派发一致，原音SHA-256不变 |
| 实际更新启动 | PASS，同一路径原子替换、完整签名与源码核对、旧进程正常退出、新进程启动 |
| 物理麦克风/自然讲话 | NOT_RUN，遵循用户要求合盖 |
| 云端API/私人音频上传 | NOT_RUN，无付费调用 |
| 公证/独立分发Gatekeeper | BLOCKED，未公证，Unnotarized Developer ID；未改系统安全设置 |

[最终CI原始收据](../ci-ab85455/receipt.json)（含逐job、测试数量、下载完整性与NOT_RUN范围）。自然段专用CI截图ZIP单次TLS下载失败，完整日志仍有PASS；本机最终签名包截图齐全，不以缺失远端图片冒充已获取。

CI：[native+foreground](https://github.com/haohongfei2001-png/saytile/actions/runs/43587863976)、[gateway](https://github.com/haohongfei2001-png/saytile/actions/runs/43587864004)、[contracts](https://github.com/haohongfei2001-png/saytile/actions/runs/43587864103)。时间敏感套件单独执行，原测试没有改成跳过。CI界面步骤没有独立AX助手的地方仍为render-only；不能用它替代本机签名包实际AX操作。

[本机总收据](local-acceptance.json) · [自然段原生收据](native-final/machine-receipt.json) · [12k时间轴](timeline-final/receipt.json) · [回退收据](rollback.json) · [档案截图](native-final/images/natural-archive.png) · [主板截图](native-final/images/natural-panel.png)

截图来自实际AppKit/SwiftUI窗口及NSTextView，使用独立合成资料，未捕获用户桌面。静音WAV用于关联与播放器控制验收，不能证明人声识别或听感。

## 失败根因与复验边界

- 480午夜旧断言要求零换行，而fixture实际有224秒间隔；已修为一处自然换行且原文不变。
- 481播放器下界1 ULP误判由真实AVAudioPlayer复现；保留全部功能断言，以相邻浮点下界处理量化误差，并隔离原生时间敏感套件。[证据](../seek-rounding/README.md)
- 783921b原始wire证明相对休眠让6.272秒音频在12秒前未发完末尾2306字节/EOS；改为累计音频时长的绝对单调时钟，未放宽deadline，最终协议52场景零违规。[证据](../connection-pacing/README.md)
- 483 Chrome单次写入正确，第一内容通知的AX快照暂不可读却提前失效。新代码仅允许这一次已发出写入进入有界只读核验，仍需两次完整同身份/光标/全文；任何第二变更拒绝，不重写或夺焦点。同一故障顺序旧代码FAIL，新代码16场景PASS。最终真实Chrome此轮快照完整且前台验收通过；暂不可读恢复本身由确定性注入验证，不冒称真实Chrome瞬时故障在新一轮重现。[证据](../web-first-observation/README.md)

失败尝试全部保留，后续PASS不覆盖之前FAIL。首次签名遇Apple时间戳服务不可用，仅同一已编译payload有界续签一次成功；仍有有效时间戳，原失败与续签脚本见[封包记录](packaging-provenance/)。

## 安装包与回退

唯一新DMG：`Saytile-0.15-mandarin-arm64.dmg`，64,920,442字节。
SHA-256：`8dda6ce70631eb802ae117027c8e955a482de8cd092bfa4270bfa8b4a77061f7`。
可执行文件SHA-256：`a88118dc0a9b04f794b9ebdde0bbdede642e8a9b2b2c1b7f5cef93ea6bd2799d`。
ASR worker仍为`9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e`；99项Helpers/Frameworks/Metal运行库逐字节一致。

本机镜像位于 `/Users/hhf/Documents/GitHub/saytile/dist/natural-paragraphs-0.15-484/`，独立Developer ID签名与DMG完整性验证PASS，未公证、未发布。已保留原478签名回退镜像及其收据；回退必须先正常退出候选，再在原路径恢复同一Bundle ID。无需导入、覆盖或删除档案数据库。

## 仍有限制

- 物理麦克风、用户口音、ASR质量重评、真实云端未在此轮验收。
- CI虚拟Mac硬件睡眠BLOCKED；真实全屏未重复验收，不以普通满屏窗口冒充系统全屏。
- 独立iCloud PR #36仍需整合段首recording UUID及break_hidden，并验证旧清单缺字段、乱序恢复与用户段界冲突。本地升级回退通过不代表新增段界跨设备恢复通过。
- 本轮仅为可运行内测候选；不宣称完整云端/发行就绪。main、RC1/RC2、正式App及其他任务未修改，不合并PR。
