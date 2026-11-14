# Saytile 0.18 交付工具：仅准备，尚未执行

这些工具改自 `/private/tmp/saytile-017-delivery`。准备阶段只读取工程脚本与既有公开工程收据/安装包，做 AST、shell 语法检查及文件 SHA-256；没有运行任一交付脚本、构建、挂载 DMG、启动/退出 App、签名、安装、读取用户数据库或 Keychain。

## 固定输入及边界

- 工作树：`/private/tmp/saytile-in-app-updates`，分支 `codex/in-app-updates`；传入最终完整源码 SHA。打包要求 HEAD 恰等于该 SHA、无 WIP、版本为 0.18。
- 基线：0.17 (488)，源码 `58bc8f96f79942881d1ae3221fd6219635833907`。取自 durable `dist/paragraph-copy-0.17-488/package.json` 与 `Saytile-0.17-mandarin-arm64.dmg`，不从正在运行的安装版复制。
- 基线 DMG SHA-256：`831059554040385710dfdd1f6c60048a2bad98f167184fc244490fe6f1bbfbf8`。
- ASR 运行库原始来源仍为 0.15 (484) / `ab8545507c79640ec3f419e33467a0263c154844`；验证 488 的全部 Helpers、Frameworks、default.metallib 与原 `runtime484.json` 的 99 项逐字节/符号链接一致。新打包只替换宿主可执行文件与宿主资源；不重编译或重签 ASR helpers/frameworks。
- Worker SHA-256：`9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e`。
- 新 build 由最终源码 `git rev-list --count HEAD` 得到，必须大于 488；没有硬编码未来 build。
- 候选身份与安装入口保持 `app.saytile.mac.mandarin-candidate` / `/Users/hhf/Applications/Saytile 中文识别候选.app`，entitlements 必须与旧版一致。
- 正式 `/Users/hhf/Applications/Saytile.app` 的 0.12 (373)、`app.saytile.mac`、完整身份指纹必须与 durable `activation.json` 相同；绝不替换它。
- 不公证、不修改 Gatekeeper、不发布、不变更用户数据、模型缓存或 Keychain。签名成功不是 Gatekeeper 通过；`validate-image.py` 记录真实评估退出码。

## 本轮更新配置

`package.py` 先赋予最终 candidate Bundle ID、版本、build 和源码 SHA，再调用工程的 `scripts/configure-update-feed.py`，然后才签名。原始公开 `packaging/update-channels.json` 复制为签入包的 `Contents/Resources/UpdateChannels.json`。

`update_contract.py` 是工具共用的只读校验，不进入产品代码：校验两个独立频道、当前 Saytile 公钥、candidate 对应的 mandarin HTTPS feed、签名要求与隐私布尔值。打包不接受其他测试 feed 或环境覆盖结果；即使环境覆盖语法合法，偏离本次正式 candidate 配置也会在签名前失败。

- Mandarin candidate feed: `https://raw.githubusercontent.com/haohongfei2001-png/saytile/codex/update-feed/mandarin/appcast.xml`。
- Standard feed 属于另一个 Bundle ID，不能交叉替换。
- `SURequireSignedFeed`、`SUVerifyUpdateBeforeExtraction`、`SUEnableAutomaticChecks` 为 true。
- `SUAutomaticallyUpdate`、`SUAllowsAutomaticUpdates`、`SUEnableSystemProfiling`、`SUSendProfileInfo` 为 false。
- `SUSignedFeedFailureExpirationInterval=0` 禁止签名失败回退为不验证；`SUScheduledCheckInterval=86400` 固定每天自动检查一次。这两个字段严格要求整数，不能用布尔值替代。
- 校验不读取私钥。包收据只记录公钥散列及公开 feed；签名私钥由既定工具/Keychain 保管。
- 新配置启用后的真实检查、无更新、更新中断、录音/编辑保存、重启和签名拒绝须由独立原生验收执行；本工具准备不宣称这些功能通过。

## 留给主任务后续执行的顺序

以下是后续执行契约，并未执行。`FULL_SHA` 必须换成最终已提交、已复核的 40 位源码 SHA。打包输出为 `/private/tmp/saytile-in-app-update-release-SHA8`，不能覆盖既有输出。

1. `python3 /private/tmp/saytile-018-delivery/package.py FULL_SHA`
   生成签名 `Saytile-0.18-mandarin-arm64.dmg`、安装提取副本、build.log、package.json、runtime484.json、packaging-scope.json。只在临时输出目录打包；不读取/安装用户 App。使用已有公开 Developer ID 身份；没有凭据时保持失败，不降级签名。
2. `python3 /private/tmp/saytile-018-delivery/rollback.py FULL_SHA`
   用现有 `scripts/mandarin/check-app-rollback.py` 及绑定散列的 fixture helper；隔离合成资料验证 **488 → 新版 → 488 → 新版**，原音哈希、全部文字版本、草稿、星标、timeline/自然段 sidecar、隐藏分界、180 秒自定义间隔、SQLite v6、默认偏好及 Keychain 服务名契约不变。测试过程禁止网络、收音与推理。输出 `rollback.json`。这不是 Sparkle 实际更新流程验收。
3. 完成主任务的最终原生更新验收与 CI 后：`python3 /private/tmp/saytile-018-delivery/activate.py --preflight FULL_SHA`
   只读校验现安装版仍是已知 488、候选已验证、回退确实测试该对二进制、DMG 哈希/签名、正式 373 指纹、公开更新配置、进程控制工具散列。状态变化会拒绝继续。
4. 主任务决定交付后才执行：`python3 /private/tmp/saytile-018-delivery/activate.py --activate FULL_SHA`
   再执行全部 preflight；仅使用既有绑定散列的控制工具优雅退出候选，原子交换同一路径并启动验证。失败交换回旧版，无法确认时保留暂存副本。**这一步会实际替换/启动候选，不是本次准备动作。** `activate.py FULL_SHA` 不会安装。

需要将输出收据及工具完整归档到 durable dist/PR 证据后，再清理临时目录。不要只保留 /tmp 路径作为最终交付证据。

## 当前验收状态

- PASS：准备文件语法；原有 durable 基线 DMG/收据散列与已知值匹配；辅助工具文件散列匹配。
- NOT_RUN：0.18 构建、签名、DMG 验证、Gatekeeper 评估、隔离迁移/回退、更新原生验收、preflight、安装、启动。
- 未读取用户录音、SQLite、设置内容、浏览器资料或密钥；未运行 ASR/麦克风/付费 API。

## 原生 UI 验证入口（仅准备）

可复用既有隔离原生 harness，不另外启动用户安装版：

```sh
python3 /private/tmp/saytile-in-app-updates/scripts/test-native-ui.py \
  --app "/private/tmp/saytile-in-app-update-release-SHA8/installed/Saytile 中文识别候选.app" \
  --output /private/tmp/saytile-in-app-update-release-SHA8/ui-review
```

该 harness 创建独立临时资料目录并传 `--data-directory ... --ui-review ...`，渲染合成记录及生产 SwiftUI/AppKit 界面；不激活用户窗口、不录音、不写系统剪贴板。`--controls` 会额外编译并调用已有 AX 验证工具，仅在主任务安排实际交互验收时添加。准备阶段没有执行此入口。

**About 截图尚无现成独立入口**：当前 `UIReview.swift` 没有 `.about` 截图，不能用已有设置截图冒充更新区验收。主任务可在自己的 UpdateReview 隔离夹具中复用 `reviewWindow(SettingsView(model: model, initialPage: .about), ...)` 产生 `settings-about-updates.png`；本工具没有修改源文件或原有 30/43 张截图计数断言。
