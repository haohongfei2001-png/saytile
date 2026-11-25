# 页面 AX 批量读取缺口：定向修复与回归

## 原始失败与诊断

保留 Actions `45552530436`、head `fb3c361` 的 Chrome 原始 FAIL。一次写入51ms成功，首个 content/selection 通知触发 `page.context_attributes`；PID/window/editor、caret=11、空选区、editable=true，页面整体比较false且context不完整。绑定当即失效；下一读恢复，AX文字完整正确。没有第二次写入。

**底层原因仍UNKNOWN**：旧日志不区分整批AX错误、属性内AX错误、缺/短响应、必需role缺失；也没有分别证明URL/title未变。不能宣称此次失败必然是cannotComplete，更不能用本机故障注入覆盖原FAIL。

没有找到可据证修复的fixture顺序问题：独立DOM见证在绑定前已await结束，随后3次完整准备+3次绑定静默读取、0通知；首写的DOM input handler只更新两个布尔计数，不导航、不改DOM结构或焦点。此处是代码与日志诊断，不是证明浏览器永远不会发生异步问题。

## 最小实现

只修改 `InputAccessibility.swift`：

- `contextAttributes` 对**明确cannotComplete**（整批或属性内）及**成功响应却nil/短批次**保留 unsupported 错误类型，传回既有有限只读确认。
- `contextAttributes` 对其他AX错误和额外批次仍返回nil；在 `pageContext` 内继续成为不完整证明而拒绝。required-role缺失、遍历预算/循环/children/语义锚不足同样不变。ancestry/window_metadata既有的nil→unsupported行为保持原样，没有泛化所有调用层。完整可读快照中的不同URL/title/context仍按原比较拒绝；读取失败本身不证明页面相同，必须靠之后两次完整证明确认。
- 页面读取错误不能覆盖已经读到的否定事实：previous选择的PID/app改变、remembered window/editor改变、明确不可编辑或非空选区优先返回明确失效。只比较已有对象和值，无新增AX读取或正常路径门槛。敏感字段、错误owning-window的guard仍位于page读取之前。
- 原协调器**逐字不变**：四次220ms、gap后两次完整新snapshot+全文witness、generation/编辑序列、第二通知/焦点/布局/取消失效、一次写入、不重播、不夺焦点、不自动发送全部保留。
- 新诊断仅固定原因及数字AX错误码，不记录属性值、页面、原文、PID或其他私人字段。

## 实际验证

最终生产Kit编译PASS；同一最终源码执行：

| 项目 | 结果 | 边界 |
| --- | --- | --- |
| 页面读取故障及安全保护 | **28/28 PASS** | 4项在新完整证明后恢复，24项安全拒绝，均只写一次并核查SQLite所有权与不重发 |
| 既有AXRole分类 | **21/21 PASS** | disabled/readonly及其他保护不退化 |
| 既有witness确认 | **16/16 PASS** | 原Safari预算不足仍拒绝，未增加等待或减少证明 |
| 扩展Swift Testing源码 | 语法PASS | 本机仅CLT，未冒称执行；由最终SHA CI运行 |
| 真实前台Chrome/Edge/Safari | **NOT_RUN** | 等待主负责人统一CI；此次不启动前台浏览器 |

页面场景覆盖整批timeout、缺批次、短批次、属性内timeout、缺required role、invalid element、额外批次、已知disabled/selection/window/editor/process变化、持续失败、仅一次完整读、第二通知、focus、layout、cancel、进程/窗口/编辑框/页面/光标/选区/前后文/敏感字段变化。合成OS元数据经生产分类函数、协调器和真实隔离SQLite，不能冒称真实AX实机故障复现。

`initial-typed-read/` 是加入已知事实优先保护前的中间编译/23场景记录，原样保留，不用来代表最终源码。最终报告位于 `final/`，逐文件源码/二进制hash在 `receipt.json`。版本号未改；主负责人审查整合后再冻结唯一577并绑定最终CI与安装包。
