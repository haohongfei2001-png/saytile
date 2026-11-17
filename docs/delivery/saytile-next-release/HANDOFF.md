# 接续本次整合

1. 从 Saytile PR #49 的分支 codex/next-release-020 获取最新源码。以 RELEASE.md 中实际 App 的 SaytileSourceRevision、CFBundleVersion 和 DMG SHA-256 识别交付物。后续收据提交不改变已构建的包。
2. 原生中文对照在 evidence/next-release-recognition。保持公开语料、原速时间轴和评分器一致。保护单路识别与用户手工编辑。
3. 当前 0.12 原版和较新的个人内测使用各自的资料空间。需要显式合并时，先正常退出，针对两份资料的副本运行 Saytile --merge-legacy-archive 当前目录 旧目录 尚不存在的新目录。命令打印收据并拒绝覆盖输入。不要直接替换正在使用的数据库。
4. iCloud 需要 Apple 团队把 iCloud.app.saytile.archive 关联到既有 Mac、iPhone App ID，并提供匹配的开发签名与配置描述文件。之后用同一隔离 Apple 测试账号依次验证 Mac 上传、新 Mac 恢复、iPhone 回听。离线/模拟器证据不能更新真实云端状态。
5. 反馈需要账户持有人登录已有 Cloudflare 账户。保持远端投递关闭，直到现有 Worker 的迁移、部署、合成 Saytile 工单在私有仓库的送达及删除均已验证。[反馈部署契约](../../FEEDBACK-REUSE.md)
6. Nearpane 的宿主改动只在该仓库 PR #11。不要同步两款应用的真实档案、缓存、权限和凭据。

当前个人体验入口是 `~/Applications/Saytile.app`。确认安装时读取 Info.plist 的 `SaytileSourceRevision` 和 release.json 即可，无需重新安装。后续若优化竞争负载，先看同一 38.8 秒长句在 30.08 秒切段精确定稿的逐次解码，以及另一处两次改写前文的实测。[逐次解码、时间轴和窗口原始记录的复算](../../../evidence/next-release-recognition/loaded-gap/README.md)。有可量化改善后再运行固定 15 条和 420 条回归。Mac 合盖期间维持物理麦克风 NOT_RUN。真实云端、私有反馈与官网发包分别推进，账户操作集中在第 4、5 项。
