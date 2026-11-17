# 工程验收

- 整合起点 703fc990 的 GitHub 五个既有作业通过。
- 待命与反馈修改的本地原生 AppModel 通过 212 项，包括权限未决定、限制、撤回、取消、升级、恢复、主动退出及幂等。14 项反馈控制器检查通过。未部署时，点击发送不会创建待发记录，重启仍保留原稿。真实私有剪贴板需要正常用户会话；沙盒中的读回失败，使用同一断言在隔离原生窗口复验通过。
- Riftlet #104 的两个 Node 测试文件通过 30/30；交付收据与删除核查的 Python 测试通过 6/6。Wrangler 缺少当前认证，尚未推送到真实服务。
- 本轮无物理麦克风采集。全部识别声源仅限有授权的公开数据和合成 fixture。

527 产品源码 `2a01a3f1c0b1b419a09a00c6cc987580f2716503` 的签名包使用临时数据目录运行。原生档案与语音板操作通过 56 次 AXPress（原有 54 次及待命偏好两次），43 张原生界面截图和 3 张参考尺寸截图。单窗口导航、原音播放/停止、搜索、星标重启保留、段落编辑与撤销、私有剪贴板及多字节选择通过。另通过 11 次外观菜单选择、边框、尺寸及恢复默认，未激活候选。图像来自生产 SwiftUI/AppKit，合成输入不能证明真人讲话。开关麦克风和云端同意框采用注入的数据，未申请或更改实际授权。

两个原程序各用两条实际可解码的合成 WAV、四个文字版本、两份编辑草稿演练旧→新→旧→新。验证 0.19（497）保留数据身份，0.12（374）保持原版的独立身份，首次打开已有自然段的资料、隐藏断行、180 秒偏好和模型缓存标记均保持。374 是可取回的 0.12 CI 包，与历史安装 373 的应用代码、包资源及构建脚本无差异。Keychain 验证服务名、Bundle ID 和签名身份，没有读取真实密钥。

iPhone 读端在 Xcode 26.6 Simulator 的两项完整端到端 UI 测试通过。两个独立缓存、按自然段搜索与回听次序等 16 个磁盘检查通过。新 Mac 离线恢复了 2 条记录、3 个编辑版本、1 份草稿和 2 份合成 WAV，共 6,488 字节，解码与校验和一致。真实 iCloud 传输了 0 条记录、0 字节。Mac 自动备份、新 Mac 从 Apple 云恢复、iPhone 真机私有库回听均为 BLOCKED。[隔离恢复收据](../../../evidence/release-private-archive/receipt.json)

Nearpane 5.15（66）独立宿主的 436 项原生、8 项依赖测试通过，公开中文录音 15.50 秒内有 17 次真实 AppKit 可见更新。这个样本首显为 4.322 秒。插件和宿主使用各自档案及授权。其原生 CI 通过，预览网站检查在目标分支与 PR 均失败，Nearpane 公证未做。[Nearpane 机器验收](https://github.com/haohongfei2001-png/nearpane/actions/runs/44048498070)

## 533 产品源码的最终验收

- **PASS**。七项 GitHub 检查全部成功。Xcode 的 Swift Testing 559/559，XCTest 30/30，另有 AppModel 212/212 项及反馈控制器 14/14 项。iPhone Air iOS 26.5 Simulator 2/2，无跳过。源代码与本机签名二进制两者均已绑定。[七项检查](../../../evidence/internal-0.20-533/pr-at-product.json) · [iOS 结果](../../../evidence/internal-0.20-533/reader/summary.json)
- **PASS**。最终签名包的原生输入板和档案共 56 次 AXPress、7 次边缘点击、43 张常规截图及 3 张参考尺寸截图。真实选区、回听、边缘点击、星标重启、点击编辑与撤销、连续段落和复制通过。另测 11 次外观菜单选择及反馈草稿与回复丢失。截图由合成档案以及授权的公开人声产生。[原生控件](../../../evidence/internal-0.20-533/native-ui/manifest.json) · [档案原图](../../../evidence/internal-0.20-533/native-ui/archive.png) · [外观](../../../evidence/internal-0.20-533/appearance/receipt.json) · [反馈](../../../evidence/internal-0.20-533/feedback/receipt.json)
- **PASS**。旧 0.12 和 0.19 各完成旧→533→旧→533。合成原音、用户编辑、草稿、段落字段、收藏、设置、模型缓存与资料身份检查通过。真实 Sparkle 安装器拒绝损坏包，将有效包原位替换并正常重启。设置中的「检查更新」读取真实公开签名 feed，当前列表为空。系统原生更新对话框的人工点击 NOT_RUN。[497](../../../evidence/internal-0.20-533/rollback-497.json) · [0.12](../../../evidence/internal-0.20-533/rollback-012.json) · [更新收据](../../../evidence/internal-0.20-533/sparkle/receipt.json)
- **PASS**。同一 533 源码在托管 Mac 使用真实 AppKit、WKWebView 和 Chrome 完成所有权、选区、增量、焦点中断与零自动发送回归。没有测试私人聊天窗口。[原生前台作业](https://github.com/haohongfei2001-png/saytile/actions/runs/44056592233/job/133947444986)
- **FAIL**。有竞争负载的长句仍出现超过两秒无有效新字。**NOT_RUN** 项包括合盖的内置麦克风、个人口音、8 GB 设备、整机功耗、物理多显示器重插与真实突然断电。[识别分项](QUALITY.md)
- **BLOCKED**。真实私有 CloudKit 跨设备恢复与反馈实际送达私有仓库仍缺外部账户条件。真实远端已传输的测试档案为零。按授权范围没有调用付费语音或文字服务。[最少账户事项](HANDOFF.md)

在 533 的真实 WindowServer 补测了 22 个场景，采集范围限定为隔离候选的两扇自有窗口；覆盖首启、权限异常、损坏模型、明暗外观、紧凑档案、模型与服务设置。两侧图均使用 688×468 个原像素展示同一段文字，左为批准原图，右为签名 533。当前固定字号和按钮比概念图小，可选边框在截图中开启。界面实测通过不等于用户已认可这些视觉差异。系统降低透明度的材质参数通过 Swift 测试，未修改用户的系统偏好。[同尺度对照](../../../evidence/internal-0.20-533/composited/reference-and-native.png) · [22 个场景](../../../evidence/internal-0.20-533/composited/receipt.json) · [深色紧凑档案](../../../evidence/internal-0.20-533/composited/archive-detail-compact-dark.png)


最终源码的连续双向缩放、最窄点击和恢复、边缘热区、编辑选区、中文输入法合成中的缩放与文字保护通过 147/147 项。相同源码的原生材质探针生成 16 种组合，保持同一编辑器、相同控件位置及字号。材质对照注入全屏环境值，真实 Space 的进入与退出另行记录。[缩放与点击](../../../evidence/internal-0.20-533/adaptive/receipt.json) · [16 组材质](../../../evidence/internal-0.20-533/glass/glass-receipt.json)


真实全屏在独立托管 Mac 上另行验证。系统的 didExitFullScreen 事件后，同时核对原生窗口与 AX 几何。浮板避开真实工具栏，退出后恢复原桌面锚点和通透状态，均为 **PASS**。系统改变第三方窗口大小时，关闭 Saytile 的同窗对照取得逐点相同的新位置，产品保留了该位置。最终 38 项通过、0 项失败、1 项 **BLOCKED**。有工具栏和无工具栏的测试窗口都被系统重新布局，因此未能在该环境触发「全屏退出后外部窗口仍处于 Saytile 上次设置的精确位置」的正向恢复情形。普通桌面的同一归属保护和恢复另有实测。专门作业以 77 退出，GitHub 记为未成功；七项常规 CI 独立计算。[三轮完整收据](../../../evidence/release-window-boundary/fullscreen-533-followup/receipt.json)
