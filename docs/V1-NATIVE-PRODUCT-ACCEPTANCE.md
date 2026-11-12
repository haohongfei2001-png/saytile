# V1 设计体验版 · 原生验收

产品源码 `ef21bda1807e9152f41fd8dbc2597cb30e28c9fc`，版本 `1.0.0-rc.2-integrated.3`，build **275**。证据来自同一个 Developer ID 签名二进制。PR 以 #18 为基线，未合并、未公证、未发布。[机器收据](../evidence/native-product-design/machine.json) · [设计规则](V1-NATIVE-PRODUCT-DESIGN.md)。

**Mac 入口**：`~/Applications/Saytile 设计体验.app`。浮板已在主屏居中、保持暂停。右侧开始说话，再点暂停；左侧立即复制。新身份不会继承 build 269 的 TCC 授权；若系统请求麦克风，只在本人决定开始录音时授权。不需要账户、密钥或第三方模型。旧的个人体验版可以照常使用；资料、音频、偏好、快捷键和钥匙串互不借用。这个包默认不占用旧版快捷键，不接管登录启动或更新订阅。不要将两个资料目录合并。

| 验收范围 | 实际结果 |
| --- | --- |
| 首启与窗口 | **PASS**。全新临时档案由正式开窗方法显示在 1920×1080 屏的 (756,391)，外框 408×298 pt；不开麦克风、不成为 key/main。真鼠标事件拖动；通过真实状态栏按钮收起/展开；两次退出重启。拖到第二块 800×1280 屏后，重启精确恢复 (-604,491,408,298)，两屏均为 2×。最后用鼠标将新体验版送回居中。[启动](../evidence/native-product-design/fresh-window.log) / [双屏轨迹](../evidence/native-product-design/two-display-gesture.log)。 |
| 主板与视觉 | **PASS（客观项）**。正文 19.5 pt、行高 26 pt、圆角 28 pt、344×234 pt 卡片、42×33.5/92.5×33.5 pt 两枚控件未改变。同文案、同尺度的 19 组实际 WindowServer 场景；源窗口与背景均属于合成夹具进程，禁止捕获桌面。原图未提供被遮挡的背景，控制背景由外部像素重建。三块无字区域的平均 RGB 字节差从 13.03 降至约 2.31；此数只衡量这三块，阴影随实际桌面变化。[左原图／右本机](../evidence/native-product-design/windows/reference-and-native.png) / [方法与原始测量](../evidence/native-product-design/windows/comparison.json)。 |
| 首次使用与系统资源 | **PASS**：空录音、取消与拒绝不会完成引导；已有非空临时文字立即完成，退出能记住。UI 拒绝/恢复为受控权限状态，实际未重置系统 TCC。现场初次查到 Apple 中文资源未安装；已有原音独立保留。只通过苹果资源接口准备资源。最终二进制对内置 6.3 秒合成音频的本机实测：首个文字在输入开始后 **1.12 秒**，EOS 前 33 次临时文字回调，输入结束约 6.56 秒，完成约 6.64 秒。另一次用正式原生文字控件观测：1.14 秒出现“连”，EOS 前 11 次可见文本更新；[5 秒实际单窗口录屏](../evidence/native-product-design/local-live.mp4)不含声音或其他窗口。[原生文字事件](../evidence/native-product-design/live-panel.json)。这不是现场人声质量或多语种准确率成绩。[原始计时](../evidence/native-product-design/on-device-synthetic.log)。 |
| 设置、档案与模型 | **PASS**。宽窗侧栏、窄窗导航、亮/暗色、原生表单滚动、服务切换、账户授权开关、密钥输入控件、编辑保存、过滤、修订、私有剪贴板。模型目录仅有 Apple、Paraformer、Qwen；实际制造残缺和局部文件，状态不允许启用，删除后磁盘占用归零。Swift 集成测试覆盖中断、续传、校验和重试；未为视觉验收重复下载数百 MB 权重。云端配置画面不代表服务已联通。[设置](../evidence/native-product-design/windows/settings.png) · [档案](../evidence/native-product-design/windows/archive-detail.png) · [模型恢复](../evidence/native-product-design/windows/models-recovery.png)。 |
| 回归 | **PASS**：426/426 Swift Testing（53 套）、126/126 AppModel。真实 AX：44 次按压、15 组交互；不可激活的原生窗口有 38+3 份渲染图。这与独立的 WindowServer 实拍分开计数。12,000 条 SQLite 合成历史支持分组、跨日回看、选区、编辑、复制及迟到修订。[控件](../evidence/native-product-design/native-controls.json) / [时间轴](../evidence/native-product-design/timeline.json)。时间轴 MOV 来自真实 AppKit 内容帧，未录制用户桌面。 |
| 数据与外部输入 | **PASS**：45 秒实时环形缓冲→VAD→WAV/SQLite；992,250 个源帧，丢帧 0，两段均完成。签名 App/旧资料关键文件元数据前后对比未变，未读取用户任何录音或文字。本机隔离 AppKit/WKWebView 28 项 PASS，零自动发送；GitHub 专用 macOS runner 另跑真实前台浏览器。 |
| 发行边界 | **BLOCKED（公开分发）**。App 和 DMG 的 Developer ID 签名、深层严格校验、磁盘校验、本机安装与实际启动均通过。Gatekeeper 对待公证下载分发的结果为 `rejected / Unnotarized Developer ID`。未修改系统策略、未移除隔离标记，未提交公证。 |
| 未执行 | **NOT_RUN**：实际拔插显示器线缆、不同物理缩放倍数、强制撤销/重新授予系统权限、本人现场讲话、收费云端识别及购买。显示器断开、缩放改变和找回原屏另有几何回归；不等于物理热插拔。 |

DMG 64,119,505 字节，SHA-256 `ca2c677f9df0d678841eb803e5f40df6a2bbc6f57f5df3952c4591f9a2817c0f`。App 可执行文件 SHA-256 `246d59c6efbdbd67f908a00004ec01770811eeb712d45d970d7acaa99baa5637`。用户只需裁决次级页面的阅读密度与实屏玻璃观感。生产版本与现有个人体验版均没有被升级。
