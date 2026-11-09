# Saytile Timeline Preview

适用于 Apple Silicon、macOS 26 及以上。工程预览使用 Developer ID 签名，公开下载分发仍需 Apple 公证。系统拒绝下载的安装包时，应等待已公证版本。

将镜像内的 Saytile Timeline Preview.app 复制到 Applications，即可与原有 Saytile 并存。预览使用独立的默认档案目录（Application Support/Saytile Timeline Preview）、偏好和钥匙串服务。首次启动收音暂停。复制文字可直接使用，向外部应用直接输入时才需要辅助功能权限。

讲话自动追加。向上滚动回看，右键正文可回到最新。有选区时左下角按钮复制选区，无选区时复制最新活动组，这是本次预览的候选范围。默认空闲两分钟后正文上移，设置中可调整间隔。

正式 RC2 档案继续由原 App 管理。工程迁移仅在完整独立副本上进行，SQLite v5 至 v6 保留原音和文字版本。回退时退出预览，用升级前的完整独立备份启动旧版本。升级后新增内容保留在单独的 v6 目录。

以后接入云端，在设置中选择讲话语言或手动选择已支持的 ASR，分别配置该 ASR 和 OpenAI 的凭据。Qwen 还需要相匹配的地域及 Workspace。分别授权云端处理，并明确同意连接检查的上传与费用后，才能进行真实联调。
