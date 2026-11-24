# Saytile 1.0.1 — 产品与发行收口中

基线 main `f3baa0a255931dbb16291690699790e3d54f8bde`，正式 1.0.0（572）产品源码 `42d8e98eaf04a56d34a36cc1aca2aff7061150f4`。

## 边界与当前裁决

HOLD：1.0.1（574）已完成 Developer ID 签名构建，产品源码 `73ad857442964437929819ba9965f6bcfdcefd27`、SourceDirty=false。最终验收进行中；缺少公证授权。当前安装 0.20（533）、用户真实资料、Keychain、模型缓存保持不变。仅隔离公开语音与合成资料。没有合并、发布、生产更新源切换。

## 已实施，待最终候选验收

- 首次使用：一次性展示本地模型准备页面，复制不强制 AX；拒绝权限后的首次点击直接进入恢复入口。
- 外部输入：修复 witness 内部暂时不可读被折叠为失效，16 场景注入通过；保持4次采样、两次完整读回、一次写入。历史Safari预算耗尽仍安全拒绝，不宣称已根治。
- 性能：原 5.451 秒首显中 4.231 秒位于首次模型解码；模型 ready 为 1.181 秒，模型输出到可见为 38 毫秒。三对历史复核未复现。本轮继续受限诊断，不盲目改变模型。
- 发行：既有 Sparkle 账户挑战签名与原公钥验证通过；修复未被 SDK 调用的 Release Notes delegate。未找到公证 profile。最终真实572→574升级、原生host重启、坏包与篡改说明拒绝已通过；6个实际Qwen权重文件及mtime保持。

## 验收口径

历史 420 段 8.53% 为加速质量回放，不应称为原速。本轮新增明确墙钟原速模式，保留原始分母与全部失败。15 段、420 段、原生界面、前台输入、升级回退、完整 CI、15 分钟连续运行在最终候选统一执行。

本机只有 Command Line Tools，无 Instruments/xctrace；完整 Swift Testing/XCTest 在完整 Xcode CI。合盖麦克风和 8GB 真机仍 NOT_RUN。

## 后续顺序

定向修复及证据 → 统一源码审查/定版 → 最终签名候选 → 原速语料与原生/CI/更新回归 → 公证与发行裁决。外部授权缺失不阻断其他工程，不伪造通过。

原 1.0.0 完整交付见 [验收报告](docs/delivery/release-100/ACCEPTANCE.md)。

## 最终验收进度

18项真实SIGKILL/迁移/写入失败与断网数据回归通过；AppModel226/226、Feedback14/14定向通过。最终原速队列已启动：16对AppKit、420+20两轮墙钟原速、15分钟连续运行串行。当前结果不能提前算PASS。完整Xcode CI在发行PR运行。

## 2026-11-25 最终候选实测进展

- 32次原生原速AB/BA均完成，16对最终文字相同；15段CER两版46/568=8.10%。当前首字P50/P95=1.052/2.126s，对照1.031/1.543s；不宣称延迟改善。中英混说单样本差异主要来自worker ready和首解码，原记录保留。
- 实际App原生控件PASS：56次AXPress、16组操作，编辑/选区/私有剪贴板/星标重启保留；22个WindowServer原生场景PASS并已查看模型页、档案和语音板。
- 0.18与533双向升级/回退、DMG独立目录离线安装及损坏资源拒绝PASS。
- 最终DMG：65 MB级；SHA256 `4b677419cfabf19ab319bb8d390a847b5f564559a872413ef24cdf9322170661`。App和DMG签名/时间戳PASS，Gatekeeper实际拒绝Unnotarized Developer ID，Staple缺票据。不得正式放行。
- 完整原速420+20两臂及15分钟连续运行仍在执行。GitHub foreground真实AppKit/WKWebView/TextEdit/Chrome/Edge/Safari通过，完整Swift Testing/XCTest与native因GitHub托管ARM容量不足、未取得runner而被取消，无测试步骤执行。下一次完整测试保持全部断言，Swift测试改标准Intel池；native仍ARM。
- 原报告调用错用manual模式已修正为显式automatic；评分、音频哈希、SHA、provider断言全部保留。Pillow缺失和旧DMG应用名不匹配为夹具环境失败，原日志保留，使用已存在Pillow环境/真实旧包名称重验通过。

- 模型真实HTTPS断点恢复PASS：仅补64KiB、六文件SHA一致、再次下载零请求，不冒称完整首次下载或系统断网切换。
- 标准Sparkle弹窗已加入独立CI桌面，复用真实控制器/默认SDK UI；本机仅编译，不抢占用户窗口，真实UI等待CI。
- 官网当前1.0.0实际下载PASS，65,662,466字节、SHA与公开发行一致；1.0.1仍未发布。
