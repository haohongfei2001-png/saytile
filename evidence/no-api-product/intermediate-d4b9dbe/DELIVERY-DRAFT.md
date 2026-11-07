> no-api.2 的拟交付结论已因确证中途音频缺口撤回；本页下方为待重写的历史草稿。当前进度见 V1-DEV-STATUS.md，新最终证据必须来自修复后的 no-api.3。

# Saytile RC2 无 API 产品交付

本页以 PR #6 的冻结运行时 `d4b9dbe812b9084f1bf31c1817c7b67095e17fc7` 为唯一最终验证对象。版本 `1.0.0-rc.2-no-api.2`；源码树 `01f8644b57935f7f9beb9759ad3e8f44dda2ce30`。后续证据提交不改变该运行时、测试或打包脚本。PR #4/#5 的有效实现保留；不合并 main，不覆盖 RC1，不开展新模型排名。

当前结论：完整短回归、安装包和30分钟合成墙钟采集已通过；**正在追加核对转换/分段后93毫秒的保存时长差异，尚未发布最终 NO_API_ENGINEERING_READY**。真实云端状态为 `LIVE_CONNECTION_PENDING`；未取得 `LIVE_PROTOCOL_VERIFIED`、`LIVE_TRANSCRIPTION_VERIFIED`、`QUALITY_VERIFIED` 或 `PRODUCTION_READY`。

## 产品范围

原生菜单栏、持续采集、独立原音、Apple 本机识别、单份可修订文字、档案搜索/修改/回放/复用、删除原音保留文字、复制及有能力边界的外部输入均保留。当前三服务核心是 Qwen Audio3.1 Message 与 AssemblyAI Universal3.6Pro 接收同一完整 PCM，唯一 GPT-6 Astra 持续融合候选文字；EOS 再核对完整证据。GPT 不收音频。Soniox 可选且默认关闭；不新增模型链。

原生设置提供三项 SecureField、Qwen 地域/Workspace、各服务处理授权与单独的合成连接检查授权。设置页面明确已准备、正在检查、部分失败及已完成，只有完整真实检查结果才能启用云端；模拟器永远不能启用。用户以后不需要终端或修改 JSON，详见[首次连接说明](V1-RC2-CONNECTION-SETUP.md)。

本轮收口还修复：历史本地失败录音继承后来云权限、换 Key 后旧录音移到新账户、取密钥期间撤权竞态、档案按钮显示本机而实际走云端，以及 VAD 分段器保留已消费 Data 前缀。录音级目的地权限使用 schema5，旧数据不回填授权；用户编辑及已拥有的 UTF-16 范围保护不放松。

## 最终验证证据

各行是不同证据层，不相加为“产品测试总数”。协议用例已包含在完整原生套件中。

| 层级 | 本轮结果 | 证据与边界 |
|---|---|---|
| 完整 Swift + 本机网络 | 378 函数 / 45 套件 / 495 参数化场景，零跳过 | [日志与源码身份](../evidence/no-api-product/final/protocol/README.md)；真实 localhost HTTP/WS，不是真实服务商 |
| 三服务协议 | 12 函数 / 52 场景；50 网络 case，零 peer 违例 | Qwen/Assembly/GPT、相同 PCM、首显/纠错/EOS、持久 WS/HTTP fallback、错误/取消/预算；fixture 证据不能评估准确率 |
| AppModel | 66 项通过 | [输入层回执](../evidence/no-api-product/final/input/receipt.json)，含连接/撤权/密钥代际、退出及异步归属 |
| 输入 | headless DOM20；原生 coordinator9；owned-range AX9 通过 | 仅独立目标；未使用用户草稿/可见浏览器；完整前台目标解析未运行 |
| WKWebView | 6/6 上下文、2 能力拒绝、零发送 | 后台 AX setter 回应但文字未改变，记 unverified 且不重放；不能宣称浏览器插入成功 |
| Apple 实际本地识别 | 8/8 完成统一候选与可派发版本 | [合成语料](../evidence/no-api-product/final/local/apple-corpus.json)，首显约1.145–1.192秒，CER 0–0.263，错误保留；不是真人/云质量 |
| 原生包 UI | 22 张图、34 AXPress、6 字段编辑（3 SecureField）、9 控件组通过 | [界面审查](../evidence/no-api-product/final/UI-REVIEW.md)；真实 SwiftUI/AppKit 控件，成功分支使用 TEST_ONLY 后端 |
| 存储/恢复 | 真 SIGKILL、Beta/RC1 迁移、拒开新库及完整副本回退 12 项通过 | [本机验证](../evidence/no-api-product/final/local/README.md)；旧音频云授权为0；合成目录 |
| 规模 | 100,000 记录 / 300,000 revisions；schema5 | partial写入p95 0.185ms、搜索148.9ms；清理仅测metadata调度，非大音频删除吞吐 |
| 安装/升级/卸载 | 实际DMG升级8项、卸载重装保留数据2项通过 | [升级](../evidence/no-api-product/final/install-upgrade.json)及[卸载](../evidence/no-api-product/final/uninstall-reinstall.json)，相同签名二进制；生产数据未访问 |
| 长时运行 | 30分钟合成采集进行中；包待命300.03秒完成 | 待命暖态RSS72,864–79,648KiB，结束74,464KiB；CPU1.94 user+0.35 sys秒；不测整机功耗 |
| 内存根因回归 | 66.7MB输入，新增峰值RSS229,376 bytes | 旧实现68,485,120 bytes；实际生产VoiceSegmenter全Kit静态链接；非墙钟采集 |
| CI | native及design均成功 | [CI证据](../evidence/no-api-product/final/protocol/ci-snapshot.json)；CI merge `5dd66d8c` 与运行时不同commit、相同tree。CI UI只渲染，本机另有真实控件交互 |

## 可安装产物

- App：正式项目 `dist/rc2-no-api.2/Saytile.app`。
- DMG：`dist/rc2-no-api.2/Saytile-1.0.0-rc.2-no-api.2-arm64.dmg`。
- DMG SHA256：`ae9fb8b9c716b4b4586c033aa5c7b667c1d3493617b849083387fba929ab5cc5`。
- 可执行文件 SHA256：`b07cabe2473e23f5f082c38e95231ec8ad49bb5449d14d0dfbefe21a83447e30`。
- Apple Silicon、macOS26+；ad-hoc 严格签名检查通过，未 Developer ID 公证。[包身份](../evidence/no-api-product/final/package-identity.json)、[交付位置与RC1保留证明](../evidence/no-api-product/final/delivery-paths.json)。

此候选没有安装覆盖 RC1。升级前需停止 App 并保留整个资料目录副本；RC1及旧schema4候选不能打开schema5，回退必须恢复完整旧副本，不合并新旧库。[安装与回退说明](V1-INSTALL.md)。

## 真实 API 后才可确认的范围

当前没有真实云请求、私人录音上传、付费调用或模型质量结论。未来只需在原生设置填入三项有效Key及正确Qwen账户地域/Workspace，分别允许服务处理，并明确授权内置合成语音检查的实际服务费用。检查有90秒、6次GPT请求和4096输出Token/次的限制，取消可停止后续请求但不能撤销已发生费用。它验证账户、协议及合成端到端，不能自动宣告准确率提升。

尚不能由本轮证据证明的事项：真实账户能力/区域/额度、实际服务协议兼容性、真人中英混说准确率和实际网络延迟、物理麦克风/设备热拔/睡眠/锁屏全过程、真实多显示器、24小时负载与整机功耗、任意第三方编辑器的前台连续输入。对应逻辑单元/通知fixture不是实机物理验证。

历史一次 AX 安全断言因当时缺分项记录仍不能归因；保留原失败及有界复查。[历史裁决](../evidence/no-api-product/local-input/ax-historical-replay/REVIEW.md)。本轮原生9+9均未重现，生产审查未发现确定的新P0/P1，但不将后来绿跑写成历史根因已修复。

当前不要求用户录音、反复点击、提供日志或参与开发排障。真实云端及上述体验边界通过之前，不宣布 `PRODUCTION_READY`，不邀请全面真人验收。
