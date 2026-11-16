# iCloud 私有档案与旧资料恢复

Mac 本地 SQLite、录音和识别在未登录或离线时仍可使用。当前安装是否具有 CloudKit 权限可在「原音与存储」查看。服务端确认数据、关联和原音校验匹配后才显示「已备份」。异常状态会区分网络、账户、容量和资料校验问题。

## 数据与恢复

同步使用私有 CKRecordZone 的增量游标，文字与音频采用独立的 SQLite 恢复队列。游标与待处理清单同时写入，先恢复文字，再按需校验和登记 CKAsset。已结束录音通过稳定 UUID 关联不可变版本、草稿、星标、自然时间组、自然段、手改段界及有序 WAV。PCM 文件帧数、WAV 文件头和 SHA-256 全部匹配才可回听。旧的无段落字段清单仍可读取。量化模型、现场录音权限、API 凭据、前台绑定与输入授权均保留在原设备。

新设备与已有资料按记录和版本 UUID 合并。冲突草稿保留成可找回的历史版本，明确的删除标记优先于离线旧副本。只删除原音时保留文字与历史。恢复记录及其日后产生的本机重识别结果均排除在自动输入之外。同一资料目录绑定原 Apple 账户，更换账户时暂停同步。iPhone 按账户隔离缓存，按自然段阅读、检索当前稿和历史稿，依照段内原音顺序播放。缓存损坏会重新校验，收到删除标记后停止访问已删除的原音。

私有数据库由 Apple 账户及 CloudKit 管理。加密与密钥恢复取决于 CloudKit 和账户保护方式；Saytile 未另行实现客户侧端到端加密。[Apple 的 CloudKit 加密说明](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)。

## 签名与隔离联调

统一内测 App 沿用已安装的 Bundle ID。Apple Developer Team 须给该 ID 和 iPhone 阅读器 ID 关联 `iCloud.app.saytile.archive` 并签发可用开发 profile。Mac 构建可接收 `SAYTILE_ICLOUD_DEVELOPMENT_PROFILE` 以及相匹配的 `SAYTILE_SIGN_IDENTITY`。签名脚本验证 profile 平台、有效期、设备、证书、容器和环境。无授权版本在创建 CKContainer 前返回。

普通生产使用需要同一容器的 Production entitlement。Development 签名只接受同时指定 `--icloud-archive-fixture` 和 `--data-directory /private/tmp/saytile-icloud-fixture-…` 的独立验收目录。测试账户只存合成档案。真实云端结果、不同设备恢复、iPhone 下载回听须由已签名设备与真实容器验证。本次本地回归使用隔离传输，详见最终验收收据。

## 原 0.12 与当前资料空间

仅在需要合并旧资料时，退出使用这两个资料目录的 Saytile，并在磁盘上准备第三个尚不存在的目录。工具只读取明确指定的两份原件，包括 SQLite 已提交的 WAL，核验写锁后在临时副本中恢复、校验和合并。成功后原子生成第三份结果，退出状态为零，标准输出为验收计数。任何输入目录不明、正在使用、输出已存在、音频校验冲突或操作中断都会保留两份原件。新产物可供独立复核。

```sh
"/Applications/Saytile.app/Contents/MacOS/Saytile" --merge-legacy-archive \
  "/绝对路径/当前资料" "/绝对路径/旧版资料" "/绝对路径/新建恢复资料"
```

这个入口不会自行搜索档案，也不会自动切换正式资料目录。核对恢复结果后才可由操作者在 Saytile 退出期间保留原目录、将结果移到当前资料位置。沿用现有应用身份和系统设置，凭据留在原 Keychain。新结果保留当前资料的辅助文件。旧资料的原音及修订在原目录内始终保留。重复 ID 不重复建档，本机明确删除的记录优先，历史删除标记也不会清除当前仍在使用的记录。
