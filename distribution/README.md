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
