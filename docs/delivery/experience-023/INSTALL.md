# Saytile 0.23（571）隔离工程候选

本包属于 Draft PR #54，产品源码 `a1ac008de50855ae0c03f30128f5b1f74269d617`，不是公开 Beta。当前安装 0.20（533）未被替换，个人数据库与录音未打开，设置及 Saytile API 凭据未修改或迁移。

- 文件：`/Users/hhf/Documents/GitHub/saytile/dist/internal-0.23-571/Saytile-0.23-571-arm64.dmg`
- SHA-256：`1bae2309ca0b1493c7111e6080c24b3b8f6a86a83066008b53c0ca2f3d42b720`
- 64,551,729 bytes，Apple Silicon / macOS 26+。
- App / DMG：Developer ID + 安全时间戳，保留现有候选 Bundle ID `app.saytile.mac.mandarin-candidate`。
- 原速验收的 App 与 DMG 中 App 为同一二进制，完整收据见 `evidence/experience-023/closure/package.json`，构建日志见同目录 `build571.log.gz`。

工程验证只把只读挂载中的 App 复制到临时 Applications 目录，并传入新建 `--data-directory`，断网 smoke 通过。请勿将此候选直接覆盖 533，也不要直接打开个人资料。恢复旧版无需回滚数据库，因为本轮从未安装替换。

本任务禁止公证；Gatekeeper 对实际 App 与 DMG 均返回 `rejected / Unnotarized Developer ID`。不关闭 Gatekeeper、不移除 quarantine、不提供绕过步骤。这个签名包用于隔离工程审查，尚不属于普通用户可放心下载的正式分发。

本轮没有新模型、付费 API、模型权重捆绑或公开更新源切换。Qwen 浅色文字是临时预览，外部应用仍要等待 EOS 正式文字；改善的 tokenizer 加载不会改变最终识别结果。限制与裁决见 [收口验收](CLOSURE.md)。
