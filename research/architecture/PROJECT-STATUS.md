# 当前工程状态（2026-11-07）

核心工程候选已在独立PR #6实现和通过隔离验收；生产main与已安装RC1未变。最终源码875f66f及其同树CI包，完整原生313/313、AppModel23/23、评分63、迁移/崩溃12、包升级8、UI渲染15均有回执。真实云质量/目标应用AX/长时功耗仍未验证，不得称为正式发布就绪。

详见 [正式交付与限制](../../evidence/single-transcript/DELIVERY.md) 和 [机器回执](../../evidence/single-transcript/final/RECEIPT.json)。以下保留之前PR5基线核查记录，不把历史失败或待开发项冒充当前状态。

---

# 架构与工程状态

2026-11-07，文档同步时核对：PR4 `45af67049ddee2553fe1929a812aecb83cc157e4`；PR5原HEAD `a9cffae52d544b8a8939fce13d735b5ec1f2bc4f`。通过git祖先核对，PR4已完整包含于PR5，不是仅根据mergeable判断。

PR5原HEAD：design contracts成功；native run 42280700932失败，276 tests/33 suites报告17 issues。因此撤销任何“完整引擎已完成/CI仅待定”的解读。当前文档提交不冒充修复了这些源码。

Mac已连接并建立独立工程工作树。新的工程PR将基于本PR，不覆盖main、已安装RC1、生产数据库或历史音频。实现与测试以新工程PR的明确SHA/receipt为准。

专用Keychain元数据查询：matching_item_count=0，configuration_present=false，cloud_enabled=false，secret_values_requested=false，permission_prompt_allowed=false。A-E真实模型对照未运行；F在Astra API下不可用。无私人音频上传、无付费模型测试。不把已有336条结果或新协议测试当作云准确率。

## 2026-11-07 PR4 最新源同步

只读核对远端：PR4 `a602236ea48f7140b57c46e916bae4c5d43f5cd9`，PR5 `fbe9349b4799883c117f61d5afc7c62ab5c82936`，PR6 `d361f1eaa915af15eaaf4097912bcc878afe29a7`。本地以 merge 保留 PR4 祖先及存储、生命周期、刷新合并、重放节奏和安全测试。旧 actor 的取消排空移植到 SingleTranscriptEngine，未恢复多评审默认链。历史 PR4 日志仍仅证明其原 SHA。

本次 PR5 同步未单独重跑测试；合并后的完整运行时及回归由独立 PR6 执行并记录。新增取消/EOS/watchdog 回归保留；音频复核测试夹具改为唯一 GPT 对真实 ASR 候选的选择，禁止创建第二音频评审。无 push、安装、生产数据、真实云调用或权限变更。

## PR6 最新上游集成（本地，2026-11-07）

PR5 同步提交：`2018c0b02abc20b9575868e32cc2f81c03d833ac`，双父 merge 包含 PR4 `a602236ea48f7140b57c46e916bae4c5d43f5cd9`。本分支以 merge 接入，保留独立引擎版本 `1.0.0-engine.single-transcript.1`，不把上游候选包标识当发布证明。

AudioCapture/Journal/Diagnostics/Lifecycle/Tap 与 PR4 源一致；Store 保留 PR4 原子恢复事务并叠加精确范围所有权；AppModel 保留刷新合并/退出保护和单份文字、安全修正。MultiRecognitionSession 仅负责调度，不恢复旧 coordinator actor；EOS 等待置于取消处理作用域，超时取消独立评审，SingleTranscriptEngine 先关闭唯一 GPT 连接，再排空仍持有的评审任务。继承 PR4 的取消排空、EOS 取消及 watchdog 回归，旧音频仲裁夹具明确改为 GPT 选择现有 ASR 证据。PR6 的 Apple Candidate ingress、离线回退与精确范围修正保留。

本次完整 Swift suite：325 tests / 39 suites，321 passed、4 环境阻断（2 合成 Keychain `.keychain(100001)`，2 静音播放“无法播放原音”），命令 exit 1，未跳过或放宽测试。AppModel probe：25/25 passed，exit 0；40 个刷新请求合并及退出后不读库检查通过。源码哈希、命令、完整新日志和具体阻断见 [本轮验证](validation/upstream-final/README.md)。上游 283 tests/25 AppModel 历史日志不冒充本次结果。未操作 integration-repo、其他工作树、main、安装包、真实资料、权限、麦克风或密钥，未上传音频、调用付费 API、推送或轮询 CI。
