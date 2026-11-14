# 官网内测下载交付 · 2026-11-15

用户明确授权官网提供内测下载。官网只更新原有入口及必要说明，未改变已批准的页面设计。

- 官网：[saytile.com/#start](https://saytile.com/#start)
- 内测：[0.18（492）](https://github.com/haohongfei2001-png/saytile/releases/tag/v0.18-beta.492)
- 官网 PR：[已合并 #45](https://github.com/haohongfei2001-png/saytile/pull/45)
- 官网合并源码：`4caf73c85e31a5c49de70c3430a84d4504aa701f`
- App 源码：`012999c2018f591f3cf9a529e4c0ae81e7b81f21`；产品 PR #44 保持 Draft，本次未修改或合并产品代码。
- DMG：64,972,638 bytes；SHA-256 `654b08e926d90c88e0cb05ff4a5c116aa6c87c6cd59f7d71c24ca028c0d5f933`。

## 验收

| 检查 | 结果 | 证据 |
|---|---|---|
| 本地隔离浏览器回归 | PASS · 26/26 | local-browser.json；7档宽度，新增下载入口与原有演示/音频/编辑 |
| 线上浏览器 | PASS · 10/10 | live-browser.json；桌面/390px，真实点击下载、完整文件与哈希核对 |
| 线上源码字节 | PASS | HTML SHA `485c7a7e6ae548319216fa60a9ca9e270a1317e5744f2b039751803096955597` 与部署源码一致 |
| 匿名 HTTP 完整下载 | PASS | public-download.json；完整 64,972,638 字节，GitHub asset digest 同值 |
| 网站 PR CI | PASS | pr-ci.json；未修改/跳过原断言 |
| GitHub Pages 部署 | PASS | deployment.json；run 43627601583，部署最终合并 SHA |
| 安装包与深度签名 | PASS | 0.18/492、ARM64、macOS26.0、源码、Developer ID 与本机既有验收包一致 |
| 独立复核 | PASS | REVIEW.md |
| 公证/Gatekeeper | BLOCKED | 未公证；Unnotarized Developer ID。下载页及发行说明明确披露 |
| 新的首次安装/物理麦克风/ASR评测 | NOT_RUN | 本任务只做官网和既有包下载，不重复或冒称新的产品验收 |

网站 CSS、运行 JS、原生代码、已安装 App、私人录音、数据库、Keychain、模型缓存、DNS 和账户方案均未变更。新安装使用独立中文候选身份，旧版数据不自动导入。此事实已在网页和发行说明注明。

线上收据单独保存于此证据分支，不为追加证据重复部署已验收的同一网页。
