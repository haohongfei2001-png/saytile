# Saytile 内测 0.14（478）· 窗口共存

产品源码：`7fd9296d8eb2bd81379bbaa7287844d0d46703d5`。基于 0.13（476），识别源代码、99 项已签名运行库和模型 worker 保持原样。本目录所在后续提交仅保存交付证据，不改变已签名产品。

## 实际行为

「设置 → 输入与快捷键 → 输入板 → 显示方式」提供「浮板 / 实体边界」。默认保持浮板。实体边界需要 macOS 辅助功能权限，仅对安全确认、允许调整的普通窗口避让；优先平移，空间不足才缩小。收起面板、切回浮板或正常退出后恢复仍属于本次调整的窗口，用户手动改过的位置受保护。

全屏时两种模式都增强原白色毛玻璃的遮挡。能通过 AX 确认附近控件且有合适空位时，语音板作有限平移；不改变字体、控件大小或用户保存的常规位置。编辑、拖动、按下鼠标或指针位于面板时不自动移动。离开全屏恢复原位。正常桌面的透明度保持原样。

## 源码与实机证据

- 本机28/28隔离原生窗口断言 PASS，使用真正的 AX、WindowServer、AppKit 全屏和生产控制器。全屏目标按钮原本与面板重叠4,160平方逻辑点；面板下移60点后重叠归零，退出全屏恢复原位。不是把满屏尺寸窗口当作系统全屏。
- 4/4材质组合 PASS；真实原生截图分别比较边框开关、普通与全屏材质。材质捕获使用受控环境注入，全屏状态检测由上面的实际系统全屏测试独立证明。[截图与像素比较](../material/README.md)
- 本机167项 AppModel 检查 PASS；原有鼠标缩放、编辑、持久化回归 PASS。
- 本机14组几何测试中的881条纯 Swift 断言 PASS。完整 Swift Testing 结果单独以最终 CI 收据为准。
- 476 → 478 → 476 隔离升级回退 PASS：2条录音、4个文字版本、2份编辑草稿、2项时间轴以及两份音频 SHA-256 全程一致；SQLite integrity=ok，外键错误0。未读取用户私人数据库、音频或 Keychain 秘密。[回退收据](rollback.json)
- [生产源码逐文件绑定](source-binding.json) · [完整本机窗口收据](../native/report.json) · [签名与打包](package.json) · [构建日志](build.log)

## 安装包

- `Saytile-0.14-mandarin-arm64.dmg`：64,720,679 字节。
- SHA-256：`7ecc7bb6bd09e4a764df091b86780fc6c4ee4d84a628017e7aeadb72af5b2212`。
- Developer ID 签名与严格完整性检查 PASS；Team `ZB9D4T66QB`，Bundle `app.saytile.mac.mandarin-candidate`。
- Gatekeeper 分发检查 BLOCKED：`Unnotarized Developer ID`。没有提交公证、修改系统安全策略或清除隔离属性。仅为本机签名内测候选，不能宣称已通过公开下载分发。
- 本机持久保存目录：`/Users/hhf/Documents/GitHub/saytile/dist/panel-boundary-0.14-478`。旧476签名包保留用于回退。

## 边界与未验项目

公开 AX 不提供 macOS 全局保留区，因此无法强制移动系统浮层、不可写窗口、其他隐藏 Space 或没有足够空间的窗口。无法确认归属、返回未知或最小尺寸不允许时拒绝调整，不盲目重试，不发送按键，不读取窗口标题/文档/用户输入。全屏应用不公开附近控件时保留位置，仍启用较不透明的玻璃。

测试只写两个自有原生 fixture 的窗口，未把用户真实窗口当作测试对象。其他第三方应用逐一兼容性 NOT_RUN；不冒称所有应用均可调整。CI 虚拟 Mac 的真实硬件睡眠 BLOCKED；本轮未执行物理睡眠。Mac 仍合盖，麦克风 NOT_RUN；云端及付费 API NOT_RUN。未修改 Nearpane、main、RC1、冻结 RC2 或正式 Saytile.app。

## 最终 CI 与安装

[Draft PR #40](https://github.com/haohongfei2001-png/saytile/pull/40)，基于 PR #37 的476产品；不合并、不发布。[最终源码的5项CI](ci/receipt.json)全部SUCCESS。Swift Testing 504/504，AppModel167项PASS；前台AppKit、WKWebView、TextEdit、Chrome输入安全，直接编辑/重开和12,003条时间轴检查通过。CI窗口边界20 PASS/0 FAIL/1 NOT_RUN（CI未启用真实全屏；本机另有28/28实际全屏覆盖）。33张原生UI截图是渲染检查，其远程AX控件助手未配置，不把截图视为所有控件交互通过。

已原位原子更新并启动 `/Users/hhf/Applications/Saytile 中文识别候选.app`，运行版本0.14（478），旧476正常退出；正式 `Saytile.app` 0.12（373）完整签名/可执行文件哈希不变。无需新增入口，不覆盖原有资料。[安装收据](install.json)

启动后约10秒的只读数字采样见[运行观察](post-launch.json)：App RSS最大106,176 KiB，CPU样本最大0.4%。这只是一次启动后观察，不是识别负载、功耗或长期稳定性评测。

物料与收据已复制到上述持久目录；[最终状态](final-status.json)区分已安装本机候选与尚未通过公证的公开发行。
