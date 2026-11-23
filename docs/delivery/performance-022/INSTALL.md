# 0.22（567）工程候选说明

**NO-GO / HOLD，不是公开发行版，也不建议替换当前 533。** 本轮不自动安装、不公证、不发布。

本机唯一新包：`/Users/hhf/Documents/GitHub/saytile/dist/internal-0.22-567/Saytile-0.22-567-arm64.dmg`。

SHA-256：`b81fa67571c956186734063be1e555223e7814dfd32d3fa54049ce829438de94`。

产品 SHA：`a90601b79e59333c97982e200dfb69e541c2bf95`；版本 0.22（567）；Bundle ID 保持 `app.saytile.mac.mandarin-candidate`。数据路径及 Keychain 服务名不变，没有打包或修改用户资料。

App 和 DMG 已签名并带安全时间戳。Gatekeeper 实测拒绝未公证 Developer ID；不要关闭 Gatekeeper、移除 quarantine 或改变安全策略来打开它。本包保留给工程复核，不向用户安排绕过式安装。

隔离验收已将此 DMG 只读挂载、复制到临时 Applications 路径，以显式合成数据目录断网启动。另用 533 和 567 的临时副本在同一合成资料上按旧→新→旧→新顺序验证原音、全部文字/编辑稿、SQLite 完整性与不确定派发；没有对用户的生产数据库执行升级。

后续只有在性能重新达标且获得公证/发行授权后，才准备正式安装替换。现阶段无需用户安装、操作或提供私人录音。继续使用现有 533。
