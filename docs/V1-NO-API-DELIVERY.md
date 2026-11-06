# Saytile RC2 无 API 产品交付 · no-api.3

验证对象为 PR #6 冻结运行时 **`ef2f8f84f377197350e6384f79af12a9b56272fd`**，tree `126d4e2b2c24ea82f016708c03f9567cb297afab`，版本 `1.0.0-rc.2-no-api.3`。后续交付提交仅加入文档与证据，不改变被测 Sources、tests、scripts、构建或打包配置。PR #4/#5 有效实现保留；main、已安装 RC1 和个人资料未改。

当前状态：**no-api.3冻结工程基线通过下述无API验证；真实云端为 `LIVE_CONNECTION_PENDING`。最新V1整体仍有并行新增的紧凑输入板目标待实现，因此本轮不在这里结束，也不宣称最新目标已全部NO_API_ENGINEERING_READY。** 未取得 LIVE_PROTOCOL_VERIFIED、LIVE_TRANSCRIPTION_VERIFIED、QUALITY_VERIFIED 或 PRODUCTION_READY。

## 产品与实质修复

菜单栏常驻与暂停恢复、独立原音保存、Apple 本机识别、单份持续修订文字、档案搜索/修改/回放/重识别/复用、只删原音保留文字和全部修改稿、复制及有能力边界的外部输入均已实现。测试只使用独立合成资料。

Qwen Audio3.1 Message 与 AssemblyAI Universal3.6Pro 接收同一完整PCM，唯一GPT-6 Astra持久文本会话持续融合候选、纠错及EOS定稿；GPT不收音频。Soniox保留为默认关闭的可选适配器。没有重新排名或增加模型链。

原生设置提供三项SecureField、Qwen地域/Workspace、逐服务处理授权和单次合成连接检查授权。保存配置不等于服务连通，只有三项真实服务和正式融合链完整通过才启用云端。未来不用终端、JSON或导出配置，详见[首次连接](V1-RC2-CONNECTION-SETUP.md)；实际账户/协议不同仍可能需要兼容修复。

本轮关闭的具体问题：

- **PCM在转换器实际领取前被丢弃。** converter可仅排出旧缓存而不请求新输入，旧采集循环却释放了已经从ring取出的新块。no-api.2的30分钟波形对照确证中途缺1486个16kHz样本，虽然ring dropped=0、WAV/SQLite自洽、CI通过。旧候选已撤回。现在保留buffer直到callback真正领取，输出依序保存，无进展明确失败；不补静音、不改prime、不重置converter。四采样率逐字节回归先红后绿。[根因与原始失败](../evidence/no-api-product/audio-buffer-ownership/README.md)。
- **旧录音继承新云权限或被发送到新账户。** schema5按录音记录服务/模型/地域/Workspace/用途及非秘密凭据代次；旧历史不回填。自动恢复按原授权、否则本机接替；手动云重识别仅授权选中录音，绑定点击时已应用配置。密钥变更前撤销运行权限，异步读key前后都检查代次。
- **VAD尾部Data保留整段已消费存储。** 不足一帧的尾部改为独立小副本；66.7MB加速输入新增峰值RSS从旧实现68,485,120 bytes降到本次262,144 bytes。不是长时或整机功耗结论。
- **首次连接闭环。** 修复真实网络协议顺序、断线取消、错误分类、持久GPT重建/HTTP回退和原生展开/费用控件；检查拥有统一实际请求预算、服务级错误和迟到回执隔离。数字、否定词、候选证据、用户稿、UTF-16所有权保护未放宽。

## 同一运行时的验证

各行分属不同证据层，不相加为产品通过率。协议用例已包含于完整原生套件；历史结果不替代本次重跑。

| 层级 | 结果 | 证据与边界 |
|---|---|---|
| 完整Swift + localhost | **379函数 / 46套件 / 499展开场景，零跳过** | [原生与协议](../evidence/no-api-product/final/protocol/README.md)，正式URLSession客户端，不是真实服务商 |
| 三服务网络协议 | 12函数 / 52场景，其中50网络case，零peer违例 | 同PCM与短尾、partial/final、持续GPT、纠错/EOS、WS重建/HTTP fallback、故障/取消/限额；另2场景因非法预算正确不联网 |
| AppModel | **66项通过** | [输入回执](../evidence/no-api-product/final/input/receipt.json)，设置/授权/凭据代次/失败/取消/退出，注入依赖 |
| 外部输入 | DOM20、普通AX9、owned-range AX9通过 | 真正隔离NSTextView与生产协调器；UTF-16增减/续写、手改/目标变化/关闭/不确定派发；已知PID选择，不冒称完整前台resolver |
| WKWebView | 上下文6/6、能力拒绝2、零发送 | 后台setter认可但DOM未改变，unverified且不重放；**不是浏览器插入成功** |
| Apple实际本地识别 | **8/8完成**候选、统一证据和可派发文字 | [合成语料](../evidence/no-api-product/final/local/apple-corpus.json)，首显1.132–1.189s，CER 0–0.263，错误保留；完成不等于准确 |
| 实际包原生UI | **22图、34 AXPress、6字段编辑（3 SecureField）、9控件组** | [界面审查](../evidence/no-api-product/final/UI-REVIEW.md)，生产SwiftUI/AppKit；成功为TEST_ONLY，不是云验收 |
| 存储和恢复 | **12项真实进程检查通过** | [本机证据](../evidence/no-api-product/final/local/README.md)，SIGKILL/迁移/零隐式云授权/旧版拒开新库/完整副本回退 |
| SQLite规模 | 10万记录 / 30万版本，schema5 | partial写p95 0.290ms；搜索143.544ms；清理时写p95 0.366ms；清理只测元数据调度 |
| 安装/升级/卸载 | **真实DMG升级8项、卸载重装2项通过** | [升级](../evidence/no-api-product/final/install-upgrade.json)、[卸载](../evidence/no-api-product/final/uninstall-reinstall.json)，同一候选二进制、RC1临时副本；不访问生产资料 |
| 隔离工程CLI | 连接设置7项、云探针4项通过 | 拒绝缺目录/错误导出/生产目录/冲突探针；空独立目录无fixture导入、无服务请求，不读取正式数据库 |
| 包待命/启动 | **300.023s**；无抢焦点启动通过 | 暖态RSS59,248–80,288KiB，结束59,248KiB；1.74 user+0.35 sys秒，约0.70%单核；独立空库，无麦克风/ASR/整机能耗 |
| 连续采集完整性 | **30分钟墙钟1800.42s，60段/179个WAV，28,800,000帧完整逐字节相等，差异0；无缺帧或多余尾帧** | [全部样本对照](../evidence/no-api-product/final/local/realtime-assessment.json)，ring dropped=0、SQLite/WAV一致、0隐式云授权；ASR/麦克风关闭，不冒称真实收音或整机功耗 |
| CI | native及design均成功，无rerun | [CI身份](../evidence/no-api-product/final/protocol/ci-snapshot.json)，379/46/499、50网络case、66 AppModel；merge760f8741与运行时不同commit、相同tree。CI只渲染窗口，控件由本机证据支持 |

## 可安装产物

App从验证后的只读DMG提取，最终独立交付位置为项目 `dist/rc2-no-api.3/`，不覆盖RC1：

- `Saytile.app`
- `Saytile-1.0.0-rc.2-no-api.3-arm64.dmg`
- DMG SHA256：`d3a3fbeef54d6a89a36364a36aed7f89bed07762a34386ce5e5356db233cbd33`
- 可执行文件SHA256：`a0bf7450a4b2a97db3bbeed916066544787b0e68d9bcaa15f57f61174e72f559`
- Apple Silicon / macOS26+；ad-hoc严格签名通过，未Developer ID公证。

[包身份](../evidence/no-api-product/final/package-identity.json)、[交付位置与RC1保护](../evidence/no-api-product/final/delivery-paths.json)。升级要保留停机后的整个资料目录副本。RC1及旧schema4候选拒开schema5；回退恢复完整旧副本，新版本新增资料另存，不合并新旧库。[安装与回退](V1-INSTALL.md)。

no-api.2已撤回并标记请勿安装；原失败与旧审计保留，不以旧绿色CI推翻确证漏音。

## 未来真实连接与明确限制

本轮 **0真实云调用、0私人音频上传、0付费请求**。未来用户主动启用时，在原生设置填三项有效Key、正确Qwen地域/Workspace，分别允许服务处理，再授权一次内置合成样本的实际服务费用。检查只发随App分发的6.272秒中英合成音频和候选文字，清空私人话题、不读历史原音。

联网阶段最长90秒、两个ASR会话、最多6次GPT实际请求、每次最多4096输出Token；WS重连与HTTP回退共享预算。这是请求上限，不保证账单金额。取消停止后续请求，不能撤销已发生费用。三服务与正式链全部通过后自动启用，不自动授予QUALITY_VERIFIED。

真实账户/模型/地域/额度、现网兼容性、真人中英混说准确率、相对单模型的改善及确认延迟须真实凭据与授权后验证。**没有证据声称双专家+GPT已经比任何单模型更准确。**

其他明确边界：

- 未采集实际麦克风或环境对话；未执行物理热拔/睡眠/锁屏/撤权、真实多显示器、24/72小时运行或整机能耗。逻辑/通知fixture不替代这些实机项目；Apple证据限当前已安装中文资源和合成语音。
- 生产前台目标解析NOT_RUN；已知目标AX不证明任意第三方兼容，WK后台写入仍unverified。历史合并安全断言因原分项计数缺失仍UNKNOWN；[原失败与复查](../evidence/no-api-product/local-input/ax-historical-replay/REVIEW.md)保留，本次9+9未复现不等于历史根因已解释。
- ad-hoc未公证；正常麦克风/辅助功能/打开确认不能由工程绕过。普通复制不需要辅助功能。

当前不要求用户录音、点击测试、提供日志、填Key或排障。无API工程就绪与完整真人/生产就绪严格分开；这些限制不转嫁为用户临时测试任务。

## 发布时收到的并行设计目标

远端提交`5d55d74d228ecb5597a4b95c9953c22389f2546c`在ef2之后新增[紧凑文字输入板规范](SAYTILE-V1-COMPACT-TRANSCRIPT-PANEL-DESIGN.md)，没有修改运行时。本次证据提交以该提交为父提交，原样保留设计。320–360pt文字优先面板、单一收音按钮与阅读保护等新要求尚不在no-api.3中；已验证22图不能替代新目标验收。工程将继续实施并单独验证新的UI，保持音频/识别契约与当前原音修复不变。此包作为已验证基线保留，不是新视觉目标的最终交付。
