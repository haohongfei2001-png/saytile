# 架构与工程状态

2026-11-07，文档同步时核对：PR4 `45af67049ddee2553fe1929a812aecb83cc157e4`；PR5原HEAD `a9cffae52d544b8a8939fce13d735b5ec1f2bc4f`。通过git祖先核对，PR4已完整包含于PR5，不是仅根据mergeable判断。

PR5原HEAD：design contracts成功；native run 42280700932失败，276 tests/33 suites报告17 issues。因此撤销任何“完整引擎已完成/CI仅待定”的解读。当前文档提交不冒充修复了这些源码。

Mac已连接并建立独立工程工作树。新的工程PR将基于本PR，不覆盖main、已安装RC1、生产数据库或历史音频。实现与测试以新工程PR的明确SHA/receipt为准。

专用Keychain元数据查询：matching_item_count=0，configuration_present=false，cloud_enabled=false，secret_values_requested=false，permission_prompt_allowed=false。A-E真实模型对照未运行；F在Astra API下不可用。无私人音频上传、无付费模型测试。不把已有336条结果或新协议测试当作云准确率。
