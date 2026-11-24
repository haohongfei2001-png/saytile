# Saytile 正式发行

版本由 packaging/VERSION 与 packaging/BUILD_NUMBER 固定；1.0.0（572）延续实际公开 0.18 和安装 533 的 app.saytile.mac.mandarin-candidate 身份。历史标识不更名，不移动资料或密钥。官网显示名称是 Saytile。

## 构建

在干净提交上指定自己的有效 Developer ID：

```sh
export SAYTILE_DEVELOPER_ID='Developer ID Application identity'
export SAYTILE_SIGN_IDENTITY="$SAYTILE_DEVELOPER_ID"
scripts/package-beta.sh
```

package-beta.sh 是保留兼容的命令名，稳定版本会生成 Saytile-1.0.0-arm64.dmg，内含安装说明和 Applications 链接。构建号不依赖 Git 提交数量。签名运行库必须从固定依赖构建，或通过 copy-verified-runtime.py 的来源、签名和逐文件摘要校验后复用。不得读取用户模型或密钥作为构建输入。

公证仅使用既有可用 profile；不输出凭据。若 Apple 接受，装订 App 后重建 DMG，再提交及装订 DMG，重新计算最终 SHA。没有 profile 时，公证/Gatekeeper 记为 BLOCKED；依本轮明确发行授权，可分发真实 Developer ID 签名包，但必须在官网和 Release 披露未公证与系统单次打开限制。不得称 Gatekeeper 通过，不关闭 Gatekeeper、不删除 quarantine。

## 放行

固定源码通过 Swift Testing/XCTest CI、原生 AppModel、同批公开原速语音、420 段质量回归、真实隔离 AX、资料升级/回退和包签名校验后，才能合并并发布。麦克风合盖未验与未配置云服务单列。

本轮不会覆盖本机 533。Sparkle 源和公钥保持原有配置；正式包进入自动更新源前另验 EdDSA、下载安装和受限首次打开。若自动更新源未完成验收，官网/GitHub 提供手动正式下载，不发布未经验证的自动更新。

## 1.0.1 更新准备

上述未公证分发说明保留为 1.0.0 的历史决定。1.0.1 在公证凭据未就绪时保留签名候选，不将公证或 Gatekeeper 记为通过，也不自动发布生产更新源。

`check-signing-availability.swift` 只查询 Keychain 属性与标准配置位置的文件数量，不读取密码、API Key 或签名私钥正文。`create-update.py` 调用 Sparkle 已配置账户在工具内部签名，并使用安装包原有公钥独立验证归档；不创建、导出或替换密钥。

在最终 App 签名、公证、Gatekeeper 及产品验收完成后准备待发布文件：

```sh
python3 distribution/create-update.py \
  --app /path/to/Saytile.app --expected-source FINAL_SOURCE_SHA \
  --sparkle .build/sparkle --notes /path/to/release-notes.txt \
  --download-url https://github.com/haohongfei2001-png/saytile/releases/download/v1.0.1/Saytile-1.0.1-update.zip \
  --output /path/to/new-update-directory
```

输出 ZIP、已签名 `appcast.xml` 与机器收据，状态固定为 `PREPARED_NOT_PUBLISHED`。更新说明以内联纯文字纳入 feed 签名，无需额外网页请求。准备工具不上传 Release，不改线上 feed；公证后的任何包修改都必须重新生成并验证归档签名和 SHA。

更新验收分两层，不能互相冒充：

- `scripts/test-release-update.py`：两个真正的旧/新二进制，保留实际版本号与构建号，使用官方 Sparkle CLI 和真实安装器。检查损坏包拒绝、安装、离线启动、两条合成档案/四个修订/原音/段落/模型缓存及手动回退。
- `scripts/test-native-update.py`：最终候选的真实 `NSApplication`、`AppUpdateController`、异步退出及 Sparkle 无参数重启。沿用严格隔离身份与虚拟 1→2 构建号，验证签名说明加载和篡改说明拒绝；这项不是实际产品版本跨度的证据，也不是标准 Sparkle 窗口的视觉验收。

两者都只改临时副本的身份/更新地址，使用独立合成资料，不访问安装 533 或其资料。既有发布公钥不变，签名账户默认 `app.saytile.updates.v1`。

公证缺少现有授权时，账户持有人只需在本机为该 Developer Team 配置一次 notarytool profile（交互式输入 app-specific password，不发送给聊天）：

```sh
xcrun notarytool store-credentials Saytile-notary --apple-id YOUR_APPLE_ID --team-id ZB9D4T66QB
```

这是凭据配置步骤，不是公证通过。后续仍须由发行流程提交最终包、等待 Apple 接受、装订并重新验证实际 App/DMG。不得以其他旧包公证替代。
