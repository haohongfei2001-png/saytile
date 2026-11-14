# Saytile 0.15（481）自然段交付

产品源码：`29ca0cc323fcdf4f1ed53ca98b546b11e98f9f31`。Draft PR [#41](https://github.com/haohongfei2001-png/saytile/pull/41) 以 PR #40 为增量基线；此证据分支只更新收据和状态，不改产品源码及已签名包。

## 使用变化

短停顿继续同一自然段，达到15秒后下一次讲话开始新段；默认60秒才开始新时间组。主板和档案共享段落，档案按整段编辑、回听、收藏。静音中不自动插入空行或抢滚动。普通改字、明确删除自动段界与撤销各自保留。

15秒按持久化的VAD活动结束/下次开始计算，不使用ASR返回时间。原有1.5秒静音结束等待已经扣除；仍包含VAD hangover与20ms帧精度，不声称精确到声学发声末点。

修复编辑冲突丢字、复制拿到未显示修订、全部原音损坏时无失败提示、旧异步成员页闪回。识别模型、运行库、默认配置保持478，本轮不宣称进一步提升ASR准确率或速度。

## 验证与证据

- PASS：签名481的17项原生检查，4份合成原音→3自然段/2时间组；6个独立AX控件检查以及3次实际收藏/播放/停止操作。跨录音emoji编辑、私有剪贴板、迟到修订、原位段界保护。截图来自实际AppKit视图，未采集用户桌面。[原生收据](native-final/machine-receipt.json)
- PASS：签名481的一万二千条历史测试，64条驻留、60秒静置、历史滚动/选区、跨午夜自然换行、实际AX复制、重新打开。[时间轴收据](timeline-final/receipt.json)
- PASS：签名478→481→478→481升级回退。2条记录、2份一秒WAV、4个文字版本、2个草稿、2个派发记录及9张既有表逻辑快照一致；两份原音SHA-256不变。主schema仍6、段落sidecar版本2；用户隐藏段界及180秒自定义设置保留；旧默认120秒→60秒。[回退收据](rollback.json)
- 本机工程回归：172项AppModel检查、11项原生SQLite案例、25,896项共享编辑断言与NSTextView撤销/重做、10项播放器Swift Testing。最终完整CI数量另行记录，不能混算这些计数。
- CI 当前 PENDING：480首轮旧午夜断言失败已纠正；481首轮已有协议normal场景12秒超时。保留[480初次失败](../ci-initial-4622f486/receipt.json)、[481首次失败](../ci-29ca0cc-attempt1/receipt.json)。同481本机13项协议测试、52个网络场景全部通过；CI根因尚不确定，未修改协议/期限/成功断言。[本机复现](../protocol-reproduction-29ca0cc/receipt.json)
- 安装当前 NOT_RUN；只读更新预检PASS。候选478及正式App保持原样。

## 安装包

DMG：`Saytile-0.15-mandarin-arm64.dmg`，64,919,616字节。
SHA-256：`ddfd7af166e702de1aa73ae6db76561081c8de4d8199946a5abb1d0eb4082bd7`。
可执行文件SHA-256：`6fb820b6a536fa09f1a76e9a90f0277b88a50b5c915d0a7fc88215f845df4f9d`。
ASR worker仍为`9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e`，全部Helpers/Frameworks/Metal运行库逐字节一致。

Developer ID签名及深度严格验证PASS；未公证，Gatekeeper独立分发检查为rejected / Unnotarized Developer ID（BLOCKED）。不更改Gatekeeper或系统安全策略，不声称正式公开发行成功。正式Saytile.app、main、RC1/RC2及其他任务不变。

## 明确限制

- NOT_RUN：真实麦克风（按用户要求合盖）、用户自然讲话、ASR质量重评、云端API。没有私人录音上传或收费调用。
- CI硬件睡眠为BLOCKED（托管虚拟Mac不支持系统睡眠），原生全屏用例本轮未跑；不以普通满屏窗口冒充系统全屏。
- iCloud PR #36尚未同步新增段首关联与break_hidden。后续整合须同步段首recording UUID并映射本机position，兼容旧清单缺字段、乱序恢复及用户段界冲突。本机回退通过不等于新增段界跨设备恢复通过。
- 481首次CI超时在本机没有复现。相对睡眠累积调度漂移是嫌疑，原CI缺wire-audit，不能将其写成已证明原因。只进行一次同源码失败作业复验，保留原始FAIL，不放宽断言。
