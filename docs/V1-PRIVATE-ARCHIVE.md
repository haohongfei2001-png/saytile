# iCloud 私有档案 · 开发候选

此分支从中文识别 0.13 的 PR #27 独立建立。正常启动且签名具备指定 Development 容器权限时，独立候选才会接触 CloudKit；指定测试数据目录的通用诊断和日常安装均不发起同步。本轮未对用户资料发起任何上传。

## 持久化与恢复

SQLite 继续保存文件所有权、时间轴和不可变文字版本。专用 SQLite outbox 只接收已结束录音的修改，版本、草稿、星标、时间分组和明确的删除操作在本机记录。重启沿用账号绑定、服务端确认的基线、增量游标与待恢复清单。分段文件遵循现有的 PCM16 WAV 布局。上传先检查文件头、帧数和 SHA-256，下载验证后才把文件登记为可回听。元数据先于原音恢复。上传使用服务器记录版本条件；收发过程中本地继续录音和编辑。删除原音会保留全部历史，删除标记优先于离线旧数据。恢复不授予云端 ASR 权限，也不会将导入的版本派发到前台应用。

云端每个录音 UUID 对应一条私有记录，保留完整版本的 UUID、来源、原文、创建时间、父版本和偏好版本。模型运行诊断、前台绑定、密钥、输入目标和模型缓存不属于备份。新设备自动从私有 zone 的更改记录恢复；下载中的游标与待恢复表在同一事务内持久化。重复的服务器回报以 UUID 去重。主动实施的本地删除会清除服务器记录的文本或音频字段，并保留删除标记。清除整个 zone 不等同于逐条删除，有本地同步历史时将暂停并显示错误。

Apple 原生 CloudKit 使用私有数据库、CKRecordZone 增量游标和 CKAsset。这里使用 CKDatabase 的逐页回报来分开元数据恢复和音频下载并在同一 SQLite 事务中提交游标。同步在应用运行时自动检查，服务中断按退避和服务端重试时间重新尝试。私有数据库限制其他用户的访问；加密与密钥恢复取决于 CloudKit 和账户保护方式。没有为此实现额外的客户端端到端加密层。详见 [Apple 的 CloudKit 加密说明](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)。

## 实机条件

开发签名需要 Apple Developer Team 给隔离 App ID `app.saytile.mac.icloud-candidate` 关联 `iCloud.app.saytile.archive` 并签发可用于此 Mac 的 Development profile，以及该 profile 对应的 Apple Development 含私钥证书。本机查到 Developer ID Application 身份；现有 Saytile 仅带麦克风 entitlement，未找到对应开发 profile。普通 Developer ID 签名不足以验证实际 iCloud 上传与恢复。

满足这些条件后，由工程在 Development 环境使用两个独立的候选资料目录和明确标记的测试档案执行上传、恢复、解码与删除回归。不要求用户提供 Apple 密码、私钥或私人录音，不操作生产容器。分别报告 Mac→真实 iCloud、真实 iCloud→全新 Mac 和 iPhone，不用本地传输替代。

## 验证

运行 `scripts/test-native.sh --filter PrivateArchiveTests` 检查原生 SQLite、WAV、冲突、重启和损坏路径。机器结果与安装包据实记录在本分支 evidence 目录。真实 Apple 账号上传和下载在签名权限就绪前均为 BLOCKED。未经授权不发布，不替换现有 App。
