# 564 原速与压力收据

`comparison.json` 由 `python3 evidence/release-021/cadence/summarize.py` 从保存的原始收据重算。CER、nearest-rank quantile、从未出现过的参考 bigram、A→B→A 和 8 进程负载标准均引用原评分脚本，不改变定义。

- `raw/normal15-complete`：最终签名 564 的 15 条完整原速结果。根目录 auto 收据与子目录同内容文件保留，但汇总每条只计一次。
- `historical15` 和 `historical-comparison.json.gz`：原 PR51 的真实 9aace8f 源码基线；不是本轮 563 运行。
- 三个有效压力配对：`repeat-old-1/new-1`、`repeat-new-2/old-2`、`closure-old-3/new-3`。压力旧 App 均为原签名 563，最新为签名 564。
- 其他压力轮次全部保留，因原负载条件不满足或工程评分并行干扰而排除。两侧原始结果、load.json 与排除理由均可复核。
- `native.log.gz`：初次第五段进程退出原始日志，内部原生诊断因旧验收器临时目录清理而缺失，原因 UNKNOWN；修复验收器保存后同段及完整 15 段复测 PASS。

`auto-*.json.gz` 包含 rawWorkerEvents（模型事件及每次解码单调时钟）、publications（实际文字流发布）、frames（实际原生文字读取）、EOS、最终档案。process.json / process-samples 保留 App + worker CPU 和同时 footprint。单个最长间隔可通过对应 cadence.json 的 start/end 时间定位，不以整体流畅描述掩盖局部失败。

同一原音哈希 `5e7b5564803cec7cb90282b0427e99cd345472b758464060bf1f2ae5ba013c04`，38.8 秒。测试是授权公开人声原速送入真实原生管线，**不是内置麦克风现场讲话**。

结论：正常 15 段准确率保持、压力三组数据齐全；压力响应性仍 FAIL、无可靠 CPU 收益。没有采用失败的发布器实验。
