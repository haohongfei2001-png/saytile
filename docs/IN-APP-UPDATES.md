# Saytile 0.18 应用内更新

基线0.17（488），产品源码58bc8f96，Draft PR43。参考Riftlet最新main b5a412f6的实际实现与正式包隔离升级证据，不能用Riftlet的成功代替Saytile验证。

使用已有固定版本Sparkle2.10.1；在菜单与关于页检查更新，后台发现更新只改变既有入口，不弹窗抢焦点。安装由用户明确选择，正常退出完成录音与草稿保存后再交给Sparkle。禁用后台自动安装、设备配置上报及额外远程发布说明下载。主语音板不增加控件或文案。

配置在签名Info.plist中，运行时不信任UserDefaults的feed覆盖；standard与mandarin按Bundle ID分别绑定更新源。Ed25519私钥仅在Saytile专属Keychain账户app.saytile.updates.v1，仓库只保存公钥。更新源当前为空，只支持真实检查，不代表已有新版获准发布。代码通过/候选生成不自动发布到源。

验收必须使用唯一fixture Bundle ID、独立资料和偏好目录：损坏包拒绝、有效更新安装重启、历史/原音/草稿/模型标记保留、无新版反馈。现有sparkle-cli脚本仅是外部替换验证，不能代替应用自身更新链。最终签名包和完整CI绑定最终源码；麦克风继续合盖未验。

官方接口依据：[SPUUpdaterDelegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html)、[发布与签名](https://sparkle-project.org/documentation/publishing/)。

## 后续更新发布约束

本轮仅接通功能及签名空更新源，不发布 App。后续获准发行时，使用对应身份的 Developer ID 包、同一 Saytile Ed25519 key 签名包和 appcast，再更新各自 feed；不得把工程分支构建自动加入源。CFBundleVersion 必须大于已安装最大 build；不能因 squash/合并后 git 提交数下降而重复或倒退。运行时还会拒绝显示版本下降、签名失败和跨身份配置。签名成功不能代替公证/Gatekeeper；公开分发仍需完整发行许可与验收。
