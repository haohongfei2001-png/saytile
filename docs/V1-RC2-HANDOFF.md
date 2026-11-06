> 以下为 PR4 candidate.2 的历史接续记录，不是当前运行时。PR6 最新统一源码、安装包及验证边界见 [无API交付](V1-NO-API-DELIVERY.md)。不沿用旧包、旧SHA或下方验证计数。

# RC2 candidate.2 接续记录 · 2026-11-07

工作树 `/Users/hhf/.codex/worktrees/saytile-fusion-quality`，本地 codex/fusion-quality，远端 research/asr-quality-2026-11-06，PR4。本轮明确只做无需密钥工作；不要调用模型、读取其他项目凭据、操作个人数据、合并或覆盖 RC1。先核对实时远端 head/CI，别把本记录的 SHA 当未来当前值。

已提交运行时 a602236、7320228955cec7bb4d24ff19700f37d1ef0ddbc3。全部修复/红绿/独立审查在 research/asr/validation/rc2-no-key。最终286 native/34 suites、25 AppModel通过。源码7320228的 candidate.2 是 sourceDirty=false，DMG a218c4c98d8eabb8b7ed5b844bb822fc3332bded4dbffd380e5dcafd9aa5c97c，binary d109e06018ae231f2a1a55c82d38505937298172c929fc7df07d86b374e382f9。dist/Saytile.app直接取自该只读DMG，未另行编译替换。旧candidate.1 App移至dist/Saytile-rc2-candidate.1.app，旧DMG仍保留。

最终包15视图/6交互组、7+4 CLI、8真实RC1 DMG升级/重启/显式回退、120秒待命均PASS。待命与合成音频资源结果区分；后者快照早于最后rate guard。已安装RC1仍8906a9d、binary18e6e5ad；不打开私人数据库。新安装文案说明现在不覆盖，未来须停机完整目录备份，schema3不支持RC1原地降级。

新包脚本必填 --expected-source / --expected-version / --expected-binary-sha256；参数来自最终DMG。所有显式测试目录同时隔离偏好；旧仅临时数据库的普通持有进程不得倒填成已隔离偏好。重跑 recipe 在 package-isolation-review.md。

运行时CI native42287027227/contracts42287027237均已成功，Swift6.3.3实际日志确认286/25；候选artifact13537518918可取。下一步提交本轮最终证据/三份状态文档并核对其PR head checks。只有文档证据变化，不重打相同运行时。最终PR正文记录最后head CI，不重复提交CI receipt引发无限循环。

真实云端始终0调用/0上传；五家凭据、公开音频处理和费用授权尚未到位。本轮不再提问、不邀请用户测试。云实际运行/质量增益/额外确认延迟均NOT_RUN；后台WebKit写入仍未确认，物理生命周期/多显示器/长时资源/公证边界保持。满足真实云端与产品条件前PR不合并。

Git普通网络曾失败，使用GitHub connector create_tree核对git write-tree，create_commit(parent实时HEAD)及update_ref(expected_sha,force=false)。读取/git/commits/SHA metadata还原本地commit对象（时区+0800、message无末尾换行），验证SHA1再update-ref。不要fetch_commit输出巨量diff，不改canonical checkout中28个既有同步副本。不要更新用户memory，除非明确要求。
