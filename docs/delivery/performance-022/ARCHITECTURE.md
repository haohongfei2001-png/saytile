# 0.22 诊断边界

继承 PR #52 的 One Active ASR Expert + Single Transcript Engine、SQLite v6、PCMJournal、用户编辑/草稿及目标输入保护。没有改变音频分段、模型权重、Qwen 解码、LocalLiveText 判定、外部投递、窗口和品牌。

独立跟踪层 `FixturePerformanceTrace` 只有同时出现 `--local-stream-probe` 与 `--performance-trace` 时启用。只在内存保存阶段名、uptime、录音测试 ID、帧数和判定类别；不收集音频、文字、SQL、凭据或用户目录。最大 50,000 条；分析器拒绝缺失/达到上限的记录，不能把截断时间线当完整证据。时间读取与追加在同一 Mutex 内，保持多线程事件顺序。

测试输出同原生 probe 的显式隔离目录绑定，不增加日常界面开关和文件。普通产品不启用、不写性能 trace。所有事件使用 `ProcessInfo.systemUptime`；worker 既有解码起止时间可直接关联。跨进程等待以 pipe 完成时刻估计下界；不会把下界当精确硬件排队时间。

新诊断代码审查时发现候选时间转 Int 可能先于既有非有限值校验触发崩溃，已移除该不必要转换。仍由原 `PrecisionFusion.validateCandidate` 拒绝坏候选；没有新增产品认证门槛或改变有效候选行为。新增测试同时验证手工稿、原音和下一条合法 final 可继续保留。

两轮 Metal 缓存试验只在历史实验提交保留。最终 `Worker.swift` 和 `qwen-verified-preview.patch` 与父产品 06997 完全相同，使用同 SHA 的签名 worker；没有以新配置偷偷保留失败实验。

构建号 567 与产品 SHA a90601b 固定。包中不包含测试公开语料或私有资料，模型仍按原合同管理。Developer ID 签名不会自动公证；本轮不调用 notarytool、不更改官网/Sparkle feed、不更改生产安装。
