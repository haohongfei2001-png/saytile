# RC2 工程接续记录

2026-11-07。当前任务是交付现有核心五服务，不做新模型排名。正式工作树 `/Users/hhf/.codex/worktrees/saytile-fusion-quality`，分支 `codex/fusion-quality`，远端 PR4 `research/asr-quality-2026-11-06`。先读取最新 PR/head/CI；main a352a1c 和已安装 RC1 不改动。canonical checkout 的 28 个预存同步副本不操作。

第一批修复已提交 0b1f61a：准入/恢复/两项取消所有权 P1、Keychain 和设置快照、Store 阶段、升级与派发集成。第二批包含真实 UI 操作、独立连接配置、生产目录子树拒绝、Swift 6.3.3 方法引用崩溃规避、270 原生用例。全部来源与前后失败日志在 research/asr/validation/rc2。

下一步：提交后从干净源码构建 1.0.0-rc.2-candidate.1 App/DMG；严格签名、实际原生 15 场景/6 组控件、7 CLI 拒绝、8 RC1→RC2 安装/升级/显式回退检查；补最终 artifact source/hash 和 CI receipt。0b1f61 CI native42265587630 失败于编译器IRGen；新 head CI 必须确认闭包改写结果，不能重用旧通过记录。仅文档证据变化可引用最后运行时源码，不循环重打包。

真实凭据仍缺失。只查询了 Saytile Keychain 元数据、0项，禁止到其他项目或私人文件寻找秘密。本轮新授权范围为 5 家核心 API、公开 6 段46.94秒及必要补例、建议 USD30 停止线（不是已批准/价格保证）。见 V1-RC2-USER-ACTIONS 与 CONNECTION-SETUP。没有调用或上传；不合并、不安装覆盖RC1、不称已具备最终真人验收条件。

Git网络传输此前失败，使用 GitHub connector 创建精确 staged tree，核对 git write-tree，再 create_commit(parent最新SHA) + update_ref(expected_sha,force=false)。从 /git/commits/SHA 获取metadata重建本地commit对象（+0800、message末尾无换行），必须先验SHA1匹配，再更新本地branch和origin ref。保留所有未提交工作。不要用fetch_commit输出整套巨量diff。最终用PR body记录CI和证据链接，不反复推送纯CI receipt引发循环验证。
