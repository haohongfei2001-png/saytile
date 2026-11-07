# Saytile V1 RC2 无 API 工程交付

当前正式工程仍为 **PR #6**。`1.0.0-rc.2-no-api.4` 的冻结工程基线已完成本机全套验证；随后收到的唯一批准界面及单按钮精修正在 `no-api.5` 接续。**当前整体尚未授予 `NO_API_ENGINEERING_READY`，真实云端为 `LIVE_CONNECTION_PENDING`。** 不授予 LIVE_PROTOCOL_VERIFIED、LIVE_TRANSCRIPTION_VERIFIED、QUALITY_VERIFIED 或 PRODUCTION_READY。

## 已完成的冻结工程基线

源码 **`1067f1ad5c5c29c698f346651c965db2169625eb`**，tree `1c59b5e95f92dd34b19d4fb390549724071114a6`。以下结果全部来自该源码，不能当作后续新界面的最终验证；[完整身份与分层证据](../evidence/no-api-product/final-no-api4-r2/delivery-manifest.json)、[独立审查](../evidence/no-api-product/final-no-api4-r2/DELIVERY-AUDIT.md)。

| 验证层 | 结果与实际范围 |
|---|---|
| 完整 Swift | 386 个函数 / 46 套件 / 506 展开场景，零跳过；本机与 CI 分别重复通过，不相加 |
| 三服务协议 | 上述套件包含 12 函数 / 52 场景，其中 50 个实际 localhost HTTP/WS case、零 peer 违例；另外 2 个非法预算场景在联网前拒绝。正式网络客户端连接协议模拟器，非真实服务商 |
| AppModel | 78 项通过；实际生产模型与明确注入的系统/网络边界 |
| 外部输入 | headless DOM20、实际隔离 NSTextView AX9、接收方改字5、owned-range AX9；不重放不确定投递，不自动发送 |
| WKWebView | 上下文6、能力拒绝2、零发送；后台 setter 认可但 DOM 不变，插入仍 UNVERIFIED，不当作浏览器输入成功 |
| Apple 本机识别 | 8/8 合成样本完成，总音频48.703秒；CER 0–0.2632，4个关键遗漏原样保留；首显1.1343–1.1809秒，输入结束至完成0.0319–0.0892秒。非真人/云质量结论 |
| 实际包原生 UI | 控件模式31图、41 AXPress、6菜单动作、5控件检查、6字段提交（3 SecureField）、12组；另20图只渲染。成功向导为 TEST_ONLY，无真实Key或服务 |
| 数据与恢复 | 12个真实进程检查：SIGKILL、迁移、零隐式云授权、RC1拒开新schema、完整停机副本回退 |
| 存储规模 | schema5、10万记录/30万版本；partial写p95 0.211ms、搜索100匹配143.866ms，清理期间写p95 0.358ms；仅合成元数据调度，非大量原音删除或界面延迟 |
| 安装升级 | 真实RC1 DMG到候选的8项检查、卸载重装2项通过；独立合成资料，无生产库读写 |
| CLI / 启动 | 连接设置7、云探针4；实际非激活主板340×240启动，不抢前台，包和执行命令有身份关联 |
| 包空闲资源 | 300.03秒，0.34 user+0.18 sys CPU秒，暖态RSS62,512–72,592KiB；无麦克风/ASR，非整机功耗 |
| 30分钟音频完整性 | **1800.48秒、60段、179个WAV、28,800,000保存帧与独立参考全部逐字节一致，0差异、无缺帧或额外尾帧；23/23最终检查通过**。ring drop0、隐式上传授权0；ASR/麦克风/扬声器关闭 |
| 音频运行资源 | 40次采样RSS15,136–18,512KiB，14.10 user+8.83 sys CPU秒（约1.274%单核时间）；合成生产保存链，非真人或电池结论 |
| CI | native42317977017及design42317977018成功，无rerun。merge8eaffdc0与1067不同commit、相同tree，base为PR5；CI只渲染20图，本机另有真实控件证据 |

所有保存PCM与独立参考SHA256均为 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`。201项运行时/构建/测试输入前后相同；协议与存储清单另外包含4项工作流/契约，因此为205项，并非源码不一致。[完整波形评估](../evidence/no-api-product/final-no-api4-r2/local/realtime-assessment.json)。

基线DMG保留于正式项目 `dist/rc2-no-api.4/Saytile-1.0.0-rc.2-no-api.4-arm64.dmg`，SHA256 `0f23176cc091d21946dc6ca5082248b779a8dcf054c9a166a21e50602387c5e0`；实际已验App可执行文件SHA256 `a8b4e9bbe14028fe8630ee1e100f65f4903b9c9830790ad452e0dad25f657b45`。这是旧视觉工程基线，不是最新批准界面的最终候选。Documents中的解包副本反复附加Finder元数据，已隔离为不可交付副本；保留原工作树中严格签名通过的App及完整DMG，不反复清属性冒称永久修复。[路径与副本边界](../evidence/no-api-product/final-no-api4-r2/delivery-paths.json)。

## 本轮继续完成的产品工作

固定架构保持：Qwen Audio3.1 Message 与 AssemblyAI Universal3.6Pro 平等接收同一完整PCM，唯一持久 GPT-6 Astra 文本会话融合证据、修正和EOS定稿；GPT不收音频。Soniox仍默认关闭，不新增模型链或排名研究。

已有修复保留：转换器实际领取前不释放输入块、VAD小尾部不保留整段数据、schema5按录音保存目的地与凭据代次、不补授旧录音云权限、用户编辑与UTF-16所有权保护、未确认投递不重放。原音保存不依赖识别或目标输入框。

最新[唯一批准规范](SAYTILE-V1-COMPACT-TRANSCRIPT-PANEL-DESIGN.md)与538e2d8的精修已继承。新的实现将状态与操作合为顶部唯一无文字按钮，保留一份可选择、可持续修订的正文，底部复制与编辑；当前段结束自动回安静待命，历史队列不会伪装成当前讲话，波形只读取真实当前电平。可选桌面小入口只展开同一输入板，默认关闭。用户选区、阅读位置与手工修改仍优先。

独立审查又发现并修复菜单栏提示订阅不全、极小屏入口定位，以及诊断参数可能误开正式资料库的问题。诊断目录现在在AppModel/Store构造前统一拒绝正式根、子树、大小写和符号链接别名；不支持的`--data-directory=…`写法明确拒绝，不能静默回到生产目录。正常无参数产品启动不受影响。新版实际预览通过36图、45次AXPress、10次状态布局检查与非抢焦点启动；诊断CLI17项、连接CLI7项通过。原生文本控件另复现并修复仅上滚2pt后自动跳底，追加内容现在保留阅读位置。以上为冻结前检查；97项AppModel与9项路径专项亦不冒充新SHA最终验收。

精确原图为 ChatGPT Library《Saytile语音输入工作台概念界面.png》（2026-11-06 23:05 UTC）。已查GitHub全部10个分支、PR1–8讨论、Release资产及[187个可达提交的历史路径](../evidence/approved-ui/reference-history.json)，当前仅有原图名称及规范引用，没有取得原图字节。[可复核查找范围](../evidence/approved-ui/reference-availability.json)。新紫色token目前按文字规范实现，**没有宣称从原图取样或完成像素比对**；旧绿色图与已舍弃品牌探索均不作当前视觉依据。

## 云端接入与实际限制

原生设置已有三项SecureField、Qwen地域/Workspace、逐服务处理许可和单次内置合成检查授权。Key只存Saytile专用Keychain。未来用户主动启用时，三家实际服务及正式融合链全部通过才启用云端；格式正确或TEST_ONLY成功不能冒充连通。不要求终端、JSON、录音或手动联调。[首次连接流程](V1-RC2-CONNECTION-SETUP.md)。

检查仅使用内置6.272秒中英合成音频，两个ASR收到完整相同音频，GPT仅收候选文字。联网最长90秒、两个ASR会话、最多6次实际GPT请求，每次最多4096输出Token，重连与HTTP回退共享预算；这是请求上限，不保证账单金额。没有授权不收费调用，不上传历史私人原音。

本轮没有真实云服务请求、付费识别或私人音频上传。实际账户/模型/地域/额度和现网兼容性未验证；**无法量化双专家+GPT相对最强单模型的准确率改善与确认延迟，未知不等于0%。**

其他明确边界：

- 未采集真实麦克风/环境对话；物理拔插、睡眠、锁屏、撤权、真实多屏、24/72小时与整机能耗未执行。逻辑与合成测试不替代这些验收。
- 生产前台resolver未执行；隔离已知PID的AX不证明任意第三方兼容，WK后台插入仍未确认。
- 旧AX合并安全断言及a684原始目标变化来源仍UNKNOWN，后续安全fixture成功不倒推历史原因。no-api.2漏音、a684红CI及主动停止的536.05秒运行完整保留，不重新标绿。
- Apple Silicon / macOS26+，ad-hoc签名，未Developer ID公证。系统打开确认、麦克风与辅助功能授权不能绕过；复制无需辅助功能。

本轮没有合并main或替换已安装RC1。并行设计操作将远端及本地main更新至99cfc1，变化仅7个设计文档/原型提示，Sources树与已安装RC1保持不变；[保护回执](../evidence/no-api-product/final-no-api4-r2/preservation-after.json)明确记录变化，不笼统称所有HEAD未变。当前不要求用户录音、点击临时测试、给日志、填Key或排障。
