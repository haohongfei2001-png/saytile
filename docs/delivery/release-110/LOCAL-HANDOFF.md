# Saytile 1.1.0（578）：最少本机接续

开发分支 [`pro/release-110`](https://github.com/haohongfei2001-png/saytile/tree/pro/release-110)，PR [#57](https://github.com/haohongfei2001-png/saytile/pull/57)。产品源码和签名候选固定为 `7eb459f1a07473ef3a2b66e6bba6b26cbc4f28ef`；随后只补测试、验证工具和交付证据，产品构建输入不变。已经纳入1.0.1候选有效修复，不需要先发行1.0.1。

## Pro已经完成，不要重做

完整源码开发、官网文案与版本配置；全部GitHub CI，包括真实原生窗口/菜单/编辑/复制、12,000条历史时间线和实际Qwen/Metal推理。实体Mac已完成18项存储中断/恢复/升级检查、真实572→578及577→578安装与回退、六个真实Qwen模型文件SHA/mtime保护，以及实际host经Sparkle退出、安装、无参数重启。更新host使用确定性测试driver；标准Sparkle窗口另有CI真实界面验收。

现有Developer ID已完成App与DMG签名、runtime/timestamp、深度签名和镜像完整性校验；签名前后的代码字节相同。签名候选和原始机器证据保存在[GitHub发行草稿](https://github.com/haohongfei2001-png/saytile/releases/tag/untagged-33577ffb9c2577452272)。这不是已发布版本；公开下载仍为1.0.0（572）。精确范围见[验证收据](../../../evidence/release-110/verification.json)。

- 候选DMG：`Saytile-1.1.0-578-signed-candidate-arm64.dmg`，65,698,914 bytes。
- SHA256：`4885779272eaf06cfb66432848b1f0db1259803c8bd2e2156ac2524d8e9cd268`。
- 本机签名App：`/private/tmp/saytile-release-110-pro-7eb459f1/.build/pro-110/distribution/stage/Saytile.app`。
- 不覆盖现有安装，不使用个人资料做测试；沿用独立worktree和临时资料目录。实际发布继续沿用现有bundle ID、公钥和资料空间。

## Codex只需补以下本机事项

1. **一轮真实使用与物理事件。** 在正常macOS会话中通过普通首次使用流程授予Saytile麦克风权限，自然讲话数分钟，检查短停顿同段、约30秒以上静音后新段；超屏整段、所选历史段、完成编辑后的复制，以及复制后继续同段。检验暂停/恢复、物理耳机/麦克风切换、睡眠/唤醒和真实窗口阅读感受。核心记录/编辑/复制不授予辅助功能权限。保留原几何、颜色、材质；不要重复全套界面研究。清空面板只隐藏显示、不截断自然段：清空后30秒内续讲，产品整段复制包含同段前文；系统选区复制仍只复制选区。
2. **暖保留及少量真实性能补验。** 观察60秒静音后复用同一worker，195秒静音后释放并能重新加载，各一次。可复用 `scripts/test-local-idle-and-fault.py --model qwen-small --scenario warm/release`；先确认正常授权环境。Pro已执行一次固定AB/BA/AB，但577/578公开文件回放都被既有麦克风权限健康检查中止，且六臂压力负载均未达预设阈值，`valid_pairs=0`。这不是性能改善或回退的证据。保持该失败原件；不要为得到好分数放松阈值或修改TCC。另用同机、同一公开38.8秒音频做少量预先声明的正常负载对照，记录首字/最长可见停顿与RSS；不重跑420段，不强求理想能耗数字。若脚本回放仍遇同一权限前提，使用正常启动、已授权的App做实际讲话/静音验证并注明测量方式。
3. **补齐公证凭据与最终安装。** 当前 `xcrun notarytool history --keychain-profile Saytile-notary` 实测exit69：该profile不存在；`spctl`实测exit3：`Unnotarized Developer ID`。账户持有人只在Mac配置凭据，密码/API Key不发送到聊天：

   ```sh
   xcrun notarytool store-credentials Saytile-notary --apple-id YOUR_APPLE_ID --team-id ZB9D4T66QB
   ```

   配置完成不等于公证通过。对现有签名App提交公证，Apple接受后装订App，再重建/签名/公证/装订DMG，核验Gatekeeper并重新计算最终SHA。无需重新实现或重编产品；若实机发现必要产品修复，则提交修复并重建对应候选。完成最终包的真实隔离安装、启动和升级；原音、编辑、收藏、设置应保留。不得关闭Gatekeeper、删除quarantine或改写源码标记来冒充通过。
4. **回传结果，由Pro完成发行。** 回传必要实机结果、公证submission状态、最终App/DMG及SHA、任何新源码提交。Pro接续PR合并、v1.1.0正式Release、官网实际版本/体积/URL/公证状态及稳定更新源；已验证的安装/重启/坏包拒绝与原公钥保护继续复用，任何包字节变化后重新生成并验证签名更新归档。公开后仅补一次真实下载、安装/升级和重启确认。不要把GitHub、官网及普通开发工作转交给Codex。

## 保持本轮产品裁决

自然讲话→面板单一文字流→自然段→完整复制。保留Qwen主线、180秒暖保留、原音、旧段落身份、用户修改和已有功能。不要重做产品研究，不换模型、不改视觉、不增加目标选择器/性能模式，不做个人词库、iCloud、iPhone、Nearpane或通用AI助手。
