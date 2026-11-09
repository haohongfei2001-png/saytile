## 连续时间轴独立预览

增加首个 ASR 回调与点击复制相遇时的空文字回归；原生 AX 探针合并节点属性读取。

macOS 26 的空闲后滚动超时已保留；本机修复后窗口/历史回归通过，双系统分别记录。

首轮本机 404 项全通过，实机双按钮与输入板回归通过。最终复测、CI 状态与截图见时间轴报告。

开发构建通过。首轮 404 项 Swift Testing 的 1 项失败已定位到新外键，修复及复测在专门报告中追踪。 [时间轴交付与验收](V1-CONTINUOUS-TIMELINE.md)

# no-api.10 最终机器验收

冻结源码 `5639058e6b178027861b18cc0521387487c919d5`。结果分为 25 项 PASS、1 项 FAIL、5 项 BLOCKED、3 项 NOT_RUN。这是验收场景分类；其中 Swift Testing 的独立计数为 401 通过、0 失败、0 跳过。

逐项收据保留测试环境、散列、原始输出及证据路径。补充运行曾在首次派发前安全拒绝，见前台拒绝日志。此前的签名包首次连接测试缺陷及修复过程保存在 PR 历史。

[无 API 封版报告](V1-NO-API-DELIVERY.md) · [机器 JSON](../evidence/no-api10/final/machine.json) · [完整 Xcode](../evidence/no-api10/final/tests/xcode.json) · [前台历史失败](../evidence/no-api10/final/input/prebind-refusal/receipt.json)
