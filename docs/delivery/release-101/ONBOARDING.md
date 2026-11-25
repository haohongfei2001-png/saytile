# 1.0.1 首次使用与权限恢复

产品改动：`746e5256a6ecfb9aba6f68224f2df12ad905be6a`，基于已发布 1.0.0 的 `f3baa0a255931dbb16291690699790e3d54f8bde`。本报告只覆盖首次使用、模型准备信息和麦克风权限恢复，不代替最终整合 SHA 的发行验收。

## 发现与修复

1. **首次使用没有实际引导。** 原代码保存 `completedFirstTranscript`，但普通启动只展示空白语音板，不展示权限用途、默认模型准备或下载体积。现在首次启动在资料恢复完成后，打开已有的本地模型设置页：说明本机识别、麦克风按开启收音时请求、自由记录与复制无需辅助功能权限，以及可选直接输入的授权入口。Qwen 位于模型列表首项，沿用现有体积、进度、暂停、继续和校验错误控件。没有另建引导向导，也没有修改主语音板。
2. **拒绝麦克风后重新打开需要先失败一次。** 原 `toggleCapture` 只对 `interrupted && denied` 直接打开系统设置；重启后状态是 `paused`，首次点击仍尝试启动。现在已拒绝或受限的暂停状态直接进入系统麦克风设置，语音按钮仍保持原来的暂停图形，并通过可访问名称说明动作。正在收音时仍可正常暂停。
3. **模型准备是否完成没有明确结论。** 模型页现在区分资源已就绪、正在准备、尚未就绪。就绪依据实际 `LocalASRService.availability`，包括权重完整性和原生运行库存在性；没有把下载请求成功视为安装完成，也不改变模型选择、自动下载或回退机制。

首次引导的展示标记与首次文字标记分开。关闭设置后不会因权限尚未允许、下载失败或尚未说话而在每次启动再次抢占窗口。已保存/恢复的文字先加载，再决定是否展示。用户仍能从原有菜单进入模型设置。

## 验证

| 项目 | 结果 | 证据与边界 |
| --- | --- | --- |
| Swift 原生编译 | PASS | Command Line Tools / SwiftBuild；不能替代完整 Xcode Swift Testing |
| AppModel 控制器 | PASS，226/226 | 原 220 项保留，增加首次展示、不重复、旧资料恢复、denied/restricted 首击恢复；`app-model.log` |
| Feedback 控制器 | PASS，14/14 | 同一既有脚本顺带执行，未改反馈行为 |
| 原有语音板手势回归 | PASS | 同一脚本验证尺寸、拖动、展开、持久化及新进程恢复；`native-probe.log` |
| 原生模型设置窗口 | PASS，2 个场景 | WindowServer 实际合成截图 `native-final/models.png`、`models-recovery.png`；脚本如实记为范围限定的 `PARTIAL_PASS` |
| 真实系统权限弹窗/现场讲话 | NOT_RUN | 使用注入权限与采集边界，不请求麦克风或真实 AX 权限 |
| 全新公开网络模型下载 | NOT_RUN | 本轮未重复 713 MB 下载；保留原有模型完整性、恢复和重试测试供最终 CI 执行 |
| 最终签名包与完整 CI | PENDING INTEGRATION | 由主负责人在统一最终源码上执行 |

源文件与测试二进制 SHA-256 见 `evidence/release-101/onboarding/receipt.json`。原生截图包是临时 ad-hoc 夹具，采用新编译可执行文件和未改的已核验 1.0.0 资源/运行库；没有安装，没有替换 533，不作为发行文件。

## 原始失败记录

- 新增恢复夹具第一次未关闭种子 Store 就打开 AppModel，正确触发既有单实例锁。仅修复夹具补充 `store.close()`，保留 `app-model-first-fixture-failure.log`；产品锁未修改。
- 沙箱运行现有私有剪贴板测试失败，WindowServer 场景进程也在到达场景前退出。授权原生环境运行相同断言和相同程序后全部通过；保留 `app-model-sandbox-pasteboard-failure.log`、`native-sandbox-failure.log` 和原收据。没有放宽复制或窗口隔离断言。
- 首张成功截图夹具继承了资源来源包的旧源码元数据。保留原收据 `failures/native-stale-metadata-receipt.json`，修正为本轮真实基线且 `source_dirty=true` 后重新采集。`receipt.json` 的源文件/二进制哈希将实际产品字节绑定到产品 commit，未宣称旧 SHA 已验证新功能。

所有资料均为隔离合成记录；未读取用户生产 SQLite、私人录音、Keychain 明文，未调用付费服务，未操作用户外部窗口。

## 整合后的补充证据

574最终签名App完成56次真实AX控件操作和22个WindowServer场景；最初ad-hoc两图的范围仍保留。真实HTTPS断点恢复已通过，详见[模型恢复报告](MODEL-DOWNLOAD-RESUME.md)：64KiB缺失尾部、6文件完整性、重开库与重复下载零请求。完整首次下载和真实系统权限弹窗仍未宣称完成。
