# RC2 无密钥运行时补审 · 2026-11-07

第一检查点 a602236 已推 PR4，design CI42285691854成功，native42285691835仍排队（不冒称通过）。随后修复待删目录阻断/误判删除、恢复错误清理及显式数据目录偏好隔离。286 native / 34 suites、25 AppModel通过，完整证据在rc2-no-key；candidate.2干净包、实际UI/CLI/upgrade8/idle120s待构建验证。用户本轮没有操作；不调用云、不合并、不覆盖RC1。继续核对实际最新远端，避免历史SHA漂移。

安装与待命脚本新增必填 --expected-source / --expected-version / --expected-binary-sha256，必须从最终只读DMG里的App校验并提取；升级脚本实际读RC1 DMG，不将tag与App源码SHA错误强等同。候选包说明已改为当前不安装及未来停机完整副本回退，schema3不可由RC1直接降级。下一步提交全部冻结源码后打包，测试后只补证据，不反复重建相同运行时。

---

# 本轮无密钥收口接续 · 2026-11-07

基于 45af670，用户明确继续无需密钥的工作。新修复与全部红/绿证据集中在 research/asr/validation/rc2-no-key；最终 283 native / 34 suites、25 AppModel 通过，所有模块冻结，独立复审进行中。版本 candidate.2；下一步提交运行时、干净打包、原生 UI/CLI/实际 RC1 DMG 升级与回退、包待命资源及新 CI。旧 candidate.1 DMG 保留。不要读私人资料、调用云 API、合并或覆盖 RC1。

主要修复：AppModel 刷新共用原始请求版本；review 取消等待所有权直到清理完成；原音恢复按错误类型区分丢失与可重试，状态变更原子、每条路径失败隔离；首次授权待定保护；重放按 PCM 时长；tap 通道和采样率校验。test-only watchdog 1 秒/观察窗 3 秒，生产 480 秒不变。120 秒合成资源快照早于最终 rate guard，不能当最终包或实际麦克风证据。

以下旧检查点保留来源，最终交付后更新顶部。

---

# RC2 工程接续记录

2026-11-07。当前任务是交付现有核心五服务，不做新模型排名。正式工作树 `/Users/hhf/.codex/worktrees/saytile-fusion-quality`，分支 `codex/fusion-quality`，远端 PR4 `research/asr-quality-2026-11-06`。先读取最新 PR/head/CI；main a352a1c 和已安装 RC1 不改动。canonical checkout 的 28 个预存同步副本不操作。

第一批修复已提交 0b1f61a：准入/恢复/两项取消所有权 P1、Keychain 和设置快照、Store 阶段、升级与派发集成。第二批包含真实 UI 操作、独立连接配置、生产目录子树拒绝、Swift 6.3.3 方法引用崩溃规避、270 原生用例。全部来源与前后失败日志在 research/asr/validation/rc2。

已完成：从干净源码 8f2d71b 构建 1.0.0-rc.2-candidate.1 App/DMG；严格签名、实际原生 15 场景/6 组控件、7 CLI 拒绝、8 RC1→RC2 安装/升级/显式回退检查，均通过；精确哈希在 delivery-manifest.json。隔离输入已完成 9 native AX / 20 DOM，WebKit 6 mutations 与不自动发送通过但实际后台插入 unverified；所有初始失败保留。运行时 8f2d71b native42269235645 / contracts42269235604 全部成功；下一步确认最终证据提交的 PR CI 并更新 PR 描述；不重建同一运行时来追逐文档提交 SHA。0b1f61 CI native42265587630 失败于编译器IRGen；新 head CI 必须确认闭包改写结果，不能重用旧通过记录。仅文档证据变化可引用最后运行时源码，不循环重打包。

真实凭据仍缺失。只查询了 Saytile Keychain 元数据、0项，禁止到其他项目或私人文件寻找秘密。本轮新授权范围为 5 家核心 API、公开 6 段46.94秒及必要补例、建议 USD30 停止线（不是已批准/价格保证）。见 V1-RC2-USER-ACTIONS 与 CONNECTION-SETUP。没有调用或上传；不合并、不安装覆盖RC1、不称已具备最终真人验收条件。

Git网络传输此前失败，使用 GitHub connector 创建精确 staged tree，核对 git write-tree，再 create_commit(parent最新SHA) + update_ref(expected_sha,force=false)。从 /git/commits/SHA 获取metadata重建本地commit对象（+0800、message末尾无换行），必须先验SHA1匹配，再更新本地branch和origin ref。保留所有未提交工作。不要用fetch_commit输出整套巨量diff。最终用PR body记录CI和证据链接，不反复推送纯CI receipt引发循环验证。
