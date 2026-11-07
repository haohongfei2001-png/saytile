# Saytile V1 RC2 · no-api.9 无密钥工程交付

**无密钥短项已通过；本版 30 分钟长跑进行中 · `LIVE_CONNECTION_PENDING`**。针对 Apple Silicon / macOS 26+ 的独立工程候选；现有安装与 GitHub 稳定发布仍为 RC1。[正式 PR #6](https://github.com/haohongfei2001-png/saytile/pull/6) 保持草稿，不修改 main。

[运行源码 `dc26fe3c`](https://github.com/haohongfei2001-png/saytile/commit/dc26fe3c59ba55994d29e99ada8d2f0b49ad9886)，源树 `f138f6733a642a2e53da22b3647aaf5744cb308b`。 [候选 DMG](../deliverables/no-api.9/Saytile-1.0.0-rc.2-no-api.9-arm64.dmg) · [校验和](../deliverables/no-api.9/SHA256SUMS.txt)。DMG：2,556,244 字节，SHA-256 `0bd16e511f3a1cf65a3618443ef3c498ca517786aa4ad07a0226451a0c2b449d`；包内可执行文件 SHA-256 `cb3b7a38dae90fccd323b57ee746baedbfcb43b457e0b30dbdcbaedffd35ed00`。

**安装边界。** 严格签名校验通过；本机启用的 Gatekeeper 对同一个 App 返回 rejected（退出码 3），因此不是可以承诺普通互联网下载后直接打开的公开发行版。[系统原始结果](../evidence/no-api9/final/gatekeeper.json)。发行方须取得可用于此产品的 Developer ID 签名、公证；不修改系统策略，不要求用户协助绕过。 [安装、升级备份和回退](V1-INSTALL.md)。

## 本版实际运行

| 链路 | 可复核的结果 |
| --- | --- |
| 独立保存与本机识别 | DMG 内 App 不用 Key、不开麦，实际将合成中文识别为文字，保存 160,310 字节 WAV，档案状态 completed/available。[包内 App 的实际结果](../evidence/no-api9/final/apple/signed-app.json)。本机 Apple 另完成 8/8 段合成音频（48.703 秒），逐条 CER 0–26.32%；首字中位 1.218 秒，讲话结束到定稿中位 0.059 秒。漏识 Mac、保存原音、充电器、修改开始时间。[逐条参考、输出和时间](../evidence/no-api9/final/apple/) |
| 三家协议与单一文字流 | 393 个原生函数、48 套件、513 个展开场景；AppModel 104 项。50 个 localhost 网络案例包含在这些检查内，未作真实云调用。 Qwen 和 AssemblyAI 的正式客户端分别向本机 WebSocket 服务端发送了相同的 32,198 字节 PCM；GPT-6 Astra 文本会话使用两路候选证据，验证三次可见修订、EOS、旧回调、断线恢复、同模型 HTTP fallback 与无依据修正拒绝。上一段等待两路 final 时新段能先保存。[协议测试与 CI](../evidence/no-api9/final/protocol/) |
| 原生连接与凭据 | 设置收集 Qwen Key、地域／Workspace、AssemblyAI 和 OpenAI Key，不要求用户写代码或 URL。真实系统 Keychain 用随机服务名与虚拟值测试读／写／删除；向导注入另行核对保存、缺项、部分成功、撤权、取消、上限与拒绝。CLI 守卫 17+7。假凭据成功不代表账户已连接。[控制器记录](../evidence/no-api9/final/input/app-model.log) |
| 原稿与原生面板 | GitHub 的[原稿测量记录](V1-ORIGINAL-REFERENCE-FIDELITY.md)对应上传的 1536×1024 JPEG，SHA-256 `58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5`。真实新窗口 408×298 pt，内有 344×234 pt 卡片及 32 pt 透明投影外圈，默认非激活。灰色双框复制 42×33.5 pt、语音胶囊 92.5×33.5 pt；底边 18 pt。[原图坐标与度量](../design/approved/original-reference-20261107.measurements.json)。原稿示例按原来分行呈现，产品实时文本自然排版，19.5 pt 正文、26 pt 行高。面板和按钮为中性白色玻璃，壁纸颜色由身后的环境而来；讲话有五根随有效声音变化的圆头竖条，VAD 结束立即回待命。37 张控件图／45 次 AXPress／10 次菜单操作；纯渲染 27 张，另各有 3 张同一生产窗口的原稿三态图。[实机图与交互](../evidence/no-api9/final/ui/REVIEW.md) · [原稿尺寸、图形及 PNG 测量](../evidence/no-api9/final/ui/reference-measurements.json)。[完整上传原稿](../design/approved/Saytile-original-visual-reference-20261107.jpeg)已逐字节核对并直接比较，不宣称逐像素复刻、实屏壁纸效果或用户审美认可。受控 WindowServer 合成中，底色冷→暖使面板内部 sRGB 三通道均值改变 (+22.51, −15.49, −5.51)，恢复冷色后回到原值；中性文字在两种底色下均可辨。只读取两个自有测试窗口，不读取桌面，不以此证明任意壁纸、物理模糊或主观还原度。[材质对照](../evidence/no-api9/compositor/) |
| 外部输入安全 | 隔离 AppKit 实测普通 AX 9、目标改字保护 5、UTF-16 所有权修正 9；无头 DOM 20。WKWebView 上下文 6、能力拒绝 2；其后台 setter 接受了请求，DOM 实际没有变化，记为未确认且未重放，发送 0 次。未碰私人草稿，未把任意前台网站列为支持。[输入记录](../evidence/no-api9/final/input/NATIVE-INPUT.md) |
| 历史、存储与异常恢复 | 实际强杀、写入失败、迁移和备份回退 12 项；保存失败不抹去已留存内容。10 万记录／30 万版本，修订写入 p95 0.234 ms、100 个搜索匹配 165.762 ms。[恢复与规模](../evidence/no-api9/local/)。删除原音保留文字、版本与用户修改。 |
| 安装、启动和资源 | 实际 RC1 → 候选升级／回退 8 项，卸载重装 2 项。隔离资料库保留原音、草稿与未确认投递；非激活启动未抢焦点或打开麦克风。空闲 300.02 秒，暖态 RSS 67,472–75,904 KiB。[安装](../evidence/no-api9/final/install-upgrade.json) · [后台](../evidence/no-api9/final/app-idle.json)。 |

已启动本版唯一的 1,800 秒实时时钟采集。运行中计数不代表通过，不借用 .6、.7、.8 的成绩。 [独立参考、探针和完整采集记录](../evidence/no-api9/local/)。

## 真实服务状态

未取得真实账户与上传授权，真实服务调用为零。双专家加 GPT 相比最强单模型的准确率改善、改善场景及附加确认延迟均未知；真实协议、真实转写、质量及生产发行状态均未通过。 [四阶段质量和延迟的未测字段](../evidence/no-api9/final/cloud-quality-boundary.json)。GPT 处理候选文字，不接收原音；Soniox 可选且默认关闭。

以后若选择启用，在“设置 → AI 识别 → 连接识别服务”保存三个账户并逐项授权。内置检查只发 6.272 秒合成样本，联网阶段最长 90 秒，最多两路语音连接及六次 GPT 请求、每次最多 4096 输出 tokens，可取消。内置界面另列 AI 输出费估算及尚未计入的输入、缓存、ASR 费用；这不是总费用承诺。失败留在本机模式，原音独立保留。通过检查不能证明真人准确率。[一次性授权及硬件边界](V1-USER-ACTIONS.md)。

物理麦克风、真实锁屏/睡眠/设备拔插、多显示器、任意第三方输入框和 24–72 小时能耗未在此候选上实测。当前不邀请真人验收。[独立审查](../evidence/no-api9/final/INDEPENDENT-REVIEW.md)。[内部 b42 过渡构建](../evidence/no-api8/intermediate-b42/README.md)、[9c4 独立过渡记录](../evidence/no-api8/intermediate-9c4/README.md)、[固定色彩 no-api.8 基准](../evidence/no-api8/README.md)与[旧版 no-api.7 数据](../evidence/no-api7/README.md) 保留独立 SHA 和原包；渐变近似稿被后到原稿取代，旧通过项不计入本版。
