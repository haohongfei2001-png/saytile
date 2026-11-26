# 1.0.1（575）最终更新与归档验收

本目录只绑定实际 Developer ID 签名包 `/private/tmp/saytile-release101-575/Saytile.app`，产品源码 `8f25ea3be642263daf22ff297f337026395840a6`，主可执行文件 SHA-256 `43548784ae92bfc80c471d409be3f4df10e265a4ea97e8e1cc858b773b41499f`。开始前主任务的原生 controls 进程已退出 0，manifest 为 PASS。

**本次更新与归档检查 PASS；公开发行仍未执行。** 公证、Gatekeeper 与发行裁决由主任务汇总，已有未配置公证 profile 的阻断不因此消失。

## 真实版本升级与缓存

`release-model-cache/receipt.json`：PASS。原样复用 `scripts/test-release-update.py`，将真实 1.0.0（572）升级至真实 1.0.1（575），再用旧版打开同一隔离资料验证回退。完整代码字节、原始签名包不变；损坏 archive 被 Sparkle 4005 拒绝；当前版本不重复安装。

两条合成录音、四份文字修订、手动编辑、未完成草稿、段落及未确认派发状态前后摘要相同。一次合并执行同时检查小型 canary 与授权研究 Qwen 缓存：6 文件、712,777,119 字节，升级及回退后的全部 SHA-256 和 mtime 与之前相同。没有下载、加载模型或读取生产缓存。

存储 probe 沿用已通过 18 项的原二进制，SHA-256 `523df7c3180b15914c9613779bcb37e92bf5ba09c22e111256957a8148b83dda`；旧收据不重写，以完整 Git 输入树相等绑定至 575 源码。

## 真实原生 host 更新

`native-update/receipt.json`：PASS。原样复用 `scripts/test-native-update.py`，运行 575 实际 host/controller、Sparkle installer 和无参数重启；独立身份的版本 alias 仍是 1→2，不与上方真实 572→575 混淆。

有效签名说明实际加载；篡改说明被 2001／3002 拒绝且没有显示回调；损坏 archive 被 4005 拒绝。退出保存、后继 PID、无参数重启、资料和偏好保留、完整签名检查通过。使用既有 deterministic driver 和禁止激活的 review 路径，没有启动标准弹窗。本轮未额外请求线上空 feed 或执行该可选设置 AX 分支；574 的独立历史证据继续保留。

## 原身份签名 ZIP 与 feed

`prepared-update/receipt.json` 的状态为 `PREPARED_NOT_PUBLISHED`。通过原 `distribution/create-update.py` 使用既有 Sparkle 账户生成，ZIP 的 Ed25519 签名由已发布公钥独立校验，feed 签名由固定 Sparkle 工具验证。

- ZIP：`/private/tmp/saytile-release101-575-update-prepared/Saytile-1.0.1-update.zip`，55,577,621 字节；SHA-256 `c6f65da61b200575bc296e9923f1ab770c745ee657ba376782d1b6d1e573cc16`。
- Feed：同目录 `appcast.xml`；SHA-256 `917e714957a8810cea8cdb5f83c9da4093a62c8fbbbe7f23e6fcfee6089706b6`。
- 内联纯文字说明逐字来自本目录 `UPDATE-NOTES-CANDIDATE.txt`，它是主任务当前说明的快照；build、version、enclosure URL 与长度匹配 ZIP。
- `verify-prepared.py` 只解包和读取：136 个文件／符号链接的字节、权限和目标，以及 67 个目录权限，与最终签名 App 完全一致。解包副本 `codesign --verify --deep --strict` PASS，Developer ID、hardened runtime 与时间戳均存在；副本未启动、未注册 Launch Services、未移除 quarantine。

ZIP 不提交 Git；本目录保留 feed、原收据、逐项 manifest、验签日志和可重跑的解包检查脚本。未来下载 URL 是待发布目标，不代表该候选已在线可用。公证、装订或任何重签名后必须重新生成 ZIP/feed，不能继续使用这些签名和摘要。

## 边界、原始问题与下一步

产品源码比较仅有 SettingsView 去除“内测”前缀，以及 BUILD_NUMBER 574→575；ASR、存储和更新源码相同。首个临时比较断言把 packaging 纳入范围，却只预期 SettingsView，因 BUILD_NUMBER 而失败；`source-scope-initial.log` 保留该判断错误，纠正后的完整 diff 与收据单独保存。它没有导致产品改动或更新测试重跑。

生产安装 0.20（533）、用户资料、录音、缓存和 Keychain 明文均未访问；未生成或导出密钥；未使用付费 API；未运行 ASR；未上传、发布、合并、公证或改变 Gatekeeper。574 全部证据和标准 UI CI 的固定 574 signed feed 原样保留。Intel 标准弹窗的真实 CI 结果、DMG、公证与回退汇总仍由主任务处理。
