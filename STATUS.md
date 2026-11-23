# Saytile 1.0.0（572）已正式发行

[正式 Release](https://github.com/haohongfei2001-png/saytile/releases/tag/v1.0.0) · [官网下载](https://saytile.com/#start) · [完整验收](docs/delivery/release-100/ACCEPTANCE.md)

## 发行状态

- PR #55 已合并到 main，合并提交 `0aa5efd4f8c14e5fe2bb6279968cdd8f6aee3553`；v1.0.0 为正式、非草稿、非预发行 Release。#52–#54 的生产实现与历史来源保留。
- 实际签名产品源码 `42d8e98eaf04a56d34a36cc1aca2aff7061150f4`，SourceDirty=false；后续提交仅更新测试夹具、验收和发行资料，193个产品文件摘要一致。
- Pages 已成功部署。真实官网25项交互、15项运行资源逐字节摘要通过；实际点击下载65,662,466字节DMG，摘要与签名实测包完全相同。
- DMG SHA-256：`60e4abf60618d510c7f99d8e92a6ec456f16840f22cc0fcd7eb74ac729c9dba2`。
- 用户当前0.20（533）未被替换；没有访问或修改真实数据库、录音或Keychain。

## 实际通过

同批15段原速CER8.10%、420段CER8.53%，全部最终文字与571基线相同。真实Qwen原速到隔离AX目标11次EOS前输入；原音、编辑、前后文字和零发送保护通过。904.8秒连续运行44/44归档；最终签名App56次按钮、9次菜单交互通过。0.18/533副本升级、回退、再升级、DMG安装及损坏包拒绝通过。

最终e988117七项CI全部SUCCESS，579项Swift Testing、30项XCTest零失败。前台AppKit、WKWebView、TextEdit、Chrome、Edge、Safari复核通过；前次Safari超时FAIL原件继续保留，不放宽保护或重发未确认文字。

## 已披露限制

Developer ID及安全时间戳通过，**尚未公证**；Gatekeeper结果为Unnotarized Developer ID。按用户本轮明确允许的发行边界提供系统单App“仍要打开”说明，不关闭Gatekeeper、不移除隔离属性。

首轮一次短句首显5.45秒，三对复核未重现，不能保证所有启动两秒内出字；长句仍会自然修订。Safari等网页在AX证据不完整时会安全暂停自动输入，文字保留且可复制。五个原有空定稿子段保留失败与重试。

Mac合盖内置麦克风、8GB实体机、付费云端/iCloud本轮NOT_RUN。Sparkle新包不自动推送，以官网和Release手动下载更新。完整原始结果、失败及发行收据位于evidence/release-100/。
