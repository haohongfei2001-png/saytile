# RC 存储与恢复工程

状态：本子系统完成实现及独立验证，等待父任务统一集成检查与 RC 判定。测试只使用独立合成目录 `/tmp/saytile-rc-storage`，未打开用户资料库。

## 根因修复

1. 已自动保存的编辑草稿未参与档案搜索：搜索包含所有文字版本及编辑草稿，保留绑定参数、LIKE 转义和原音删除后的检索。
2. 第二实例打开同库会重置正在录音、识别及输入绑定：新增内核 flock 独占所有权；显式 `close()` 后允许重新打开，关闭后数据库访问返回错误。系统自动在进程被杀时释放锁。调用者应先停止采集、识别、回放并持久保存草稿，再关闭。
3. 建表与升级不在事务中：Beta schema 1 → RC schema 2 的 DDL、索引和版本号同事务提交；迁移失败全部回滚；拒绝未知新版本发生在写入 SQLite PRAGMA 前。Beta 版本不能降级打开 RC schema 2。
4. 部分识别稿清理会构建全库 NOT IN 集合：改用关联 EXISTS 及索引，降低长期档案对实时写入的影响。
5. 输入板来源被最新 30 条截断：提供按本次起点与明确带回历史 ID 的分页及计数 API，按时间、ID 稳定降序排序；UI 集成由父任务完成。
6. 可读但字段损坏的行使用强制解包：记录、版本、原音索引解码返回可处理错误，避免进程崩溃。
7. 整批原音清理同步占据 Store actor：每条物理删除和事务完成后让出执行权，并逐条重新校验收藏、活跃录音、识别状态和租约。删除恢复按 256 条扫描；空间统计在后台扫描文件，避免阻塞录音登记。
8. 原音根目录或 SQLite 文件是符号链接时，初始化可能先接触指向的外部路径：在创建或打开前拒绝存储叶节点符号链接；允许 `/tmp → /private/tmp` 等系统父路径别名。音频 journal 创建前的 FD 锚定由音频子任务修复。

## 已完成验证

- `SAYTILE_TEST_SCRATCH=/tmp/saytile-rc-storage/native SAYTILE_TEST_LOG=evidence/rc/storage-native-tests.log scripts/test-native.sh --filter 'Store|store'`：最新 56 项筛选测试通过（含新增直接输入队列及音频关闭后 Store 访问测试）。
- `python3 scripts/test-rc-storage-processes.py`：9 项真实子进程场景通过。覆盖内核文件大小限制引发 SQLite 写失败、错误写事务不留下部分版本、解除限制后继续写入；第二进程拒绝打开；SIGKILL 后持久 WAL 恢复；未提交事务回滚；删除意图恢复；旧绑定失效且未确认派发不重放。
- 升级测试从正式 `v1.0.0-beta.1` tag 提取实际 `Models/Store/StoreSQLite` 源码，编译独立旧版写入器，创建含原音、识别版本、修改稿、草稿、收藏及派发记录的 schema 1 库，再由当前 RC 源码打开。不是用新 schema 冒充旧版。
- Native 测试额外覆盖 SQLite `max_page_count` 触发 FULL、升级 DDL 失败回滚、未来版本数据库内容和 journal 模式不变、损坏字段返回错误、同实例关闭后拒绝写入、135 段当前记录与历史显式复用分页。

证据：`evidence/rc/storage-native-tests.log`、`storage-processes.log/json`。首次编译碰到并行开发中的输入模块错误，保留在 `storage-native-compile-failure.log`；该问题由输入负责人修复后通过。

## 档案规模及响应

`scripts/test-rc-storage-scale.sh` 使用 100,000 条记录、300,000 个文字版本，运行实际 Store 查询、SQLite FULL 同步写入及清理操作：

| 项目 | 此次结果 |
|---|---:|
| 200 次部分稿写入 p50 / p95 / 最大 | 0.072 / 0.140 / 1.210 ms |
| 中文子串搜索，返回 100 条 | 110.5 ms |
| 最后一页 100 条 | 41.8 ms |
| 自动恢复领取一条 | 18.6 ms |
| 清理 499 条期间并发草稿写入 p95 / 最大 | 0.239 / 0.341 ms |
| 该独立进程峰值 RSS | 97,976,320 bytes，约 93.4 MiB |

证据：`evidence/rc/storage-scale.json`、`storage-scale-resources.log`。这是合成档案上的存储测量，不代表全 App、ASR、整机功耗或 72 小时真人使用。

## 延迟识别的直接输入候选

新增 `directInputCandidates(bindingID:createdSince:limit:)`，按绑定后的最旧新讲话优先查询每条最新 final 文本，排除空 final、无稳定稿、非活跃绑定及与已预留游标前缀相同的文字。前缀修订仍返回候选，由既有 `reserveDispatch` 拒绝并使绑定失效；未确认、失败及已尝试的相同范围不自动重放。

65 条新讲话以每批 20 条排空的原生回归测试通过，证明延迟 ASR 不受输入板最新 30 条限制；另覆盖重复 final 排除、前缀改写、重启绑定失效及易变尾部排除。`revision_latest_final` 部分索引支持此查询，不改变用户选中的文字版本。AppModel 接入由父任务完成。

## 跨子系统审查交接

- 音频恢复用物理文件长度生成 WAV32 头之前必须检查范围，否则 >4 GB 稀疏损坏文件可触发整数转换崩溃；已交音频负责人修复并添加边界测试。
- journal 必须在创建前拒绝/隔离符号链接，不能依赖创建之后的 Store 路径校验；已交音频负责人使用目录 FD/openat 处理。
- 手动重识别普通错误路径需要取消并等待 ASR 完成后再释放租约，避免 Store 关闭后还有生产者回调；已交音频负责人。
- 播放 generation 校验和 shutdown 中先结束音频再关闭 Store 的顺序已检查；真实设备/锁屏、ASR 质量及最终窗口验收由对应负责人提供独立证据。

没有修改 `archive/`，没有读取或上传真实录音，没有自行提交 Git；由父任务统一总状态和提交。
