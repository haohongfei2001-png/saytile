# 架构与工程状态

2026-11-07，文档同步时核对：PR4 `45af67049ddee2553fe1929a812aecb83cc157e4`；PR5原HEAD `a9cffae52d544b8a8939fce13d735b5ec1f2bc4f`。通过git祖先核对，PR4已完整包含于PR5，不是仅根据mergeable判断。

PR5原HEAD：design contracts成功；native run 42280700932失败，276 tests/33 suites报告17 issues。因此撤销任何“完整引擎已完成/CI仅待定”的解读。当前文档提交不冒充修复了这些源码。

Mac已连接并建立独立工程工作树。新的工程PR将基于本PR，不覆盖main、已安装RC1、生产数据库或历史音频。实现与测试以新工程PR的明确SHA/receipt为准。

专用Keychain元数据查询：matching_item_count=0，configuration_present=false，cloud_enabled=false，secret_values_requested=false，permission_prompt_allowed=false。A-E真实模型对照未运行；F在Astra API下不可用。无私人音频上传、无付费模型测试。不把已有336条结果或新协议测试当作云准确率。

## 2026-11-07 PR4 最新源同步

只读核对远端：PR4 `a602236ea48f7140b57c46e916bae4c5d43f5cd9`，PR5 `fbe9349b4799883c117f61d5afc7c62ab5c82936`，PR6 `d361f1eaa915af15eaaf4097912bcc878afe29a7`。本地以 merge 保留 PR4 祖先及存储、生命周期、刷新合并、重放节奏和安全测试。旧 actor 的取消排空移植到 SingleTranscriptEngine，未恢复多评审默认链。历史 PR4 日志仍仅证明其原 SHA。

本次 PR5 同步未单独重跑测试；合并后的完整运行时及回归由独立 PR6 执行并记录。新增取消/EOS/watchdog 回归保留；音频复核测试夹具改为唯一 GPT 对真实 ASR 候选的选择，禁止创建第二音频评审。无 push、安装、生产数据、真实云调用或权限变更。
