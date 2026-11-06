# RC2 一次性连接设置（不替换 RC1）

在工程方准备好干净的 RC2 候选之后，用同一份原生识别设置保存五项核心服务的连接信息。这里只做连接设置，不录音、不上传、不调用模型、不安装到 Applications，也不打开原有资料目录。不是新的账号或接入向导。

## 用户需要完成的一次设置

从正式工程目录运行：

```sh
bash scripts/open-rc2-connection-setup.sh
```

脚本默认使用该工程 `dist/Saytile.app`；也可传入本工程 dist 内候选 App 的绝对路径。脚本检查 RC2 版本与干净构建标志，不使用已安装 RC1，不调整系统安全设置。不要将密钥贴进聊天、终端命令或公开文件。

在打开的原生窗口中：

1. 使用最高质量模式，准备 Qwen 中文、AssemblyAI 英文、Astra 融合、Gemini 原音复核、ElevenLabs Scribe 定稿。填写各服务 API Key 后点击保存密钥；Qwen 另选地域并填写对应 Workspace ID。
2. 阅读并选择各项服务处理授权，启用高质量云端识别，点击“保存并应用识别设置”。Soniox/Meta 保留为可选能力，本次核心接通不要求新增它们的凭据。
3. 点击“完成连接设置”。只导出已应用的非秘密配置并退出。密钥直接保存至 Saytile 专用 Keychain，配置文件没有密钥值。

脚本会打印本次配置路径，例如 `dist/connection-setup.XXXXXX/recognition-config.json`。整个目录被 Git 忽略；配置中的地域、Workspace 和话题也不要擅自提交到公开仓库。正常关闭按钮或窗口红色关闭按钮都会退出独立进程并清除临时偏好。关闭前已经明确保存的密钥会保留；未完成时不会导出配置或宣称已接通。

**完成连接设置不代表真实云验证通过，也不自动开始付费调用。** 工程方仍需用户对已有合法测试音频的处理及少量端到端调用预算作集中授权，然后自行执行联调。用户无需录音、试错、提供日志或替工程排障。实际调用完成前不覆盖稳定 RC1。

## 工程边界与复现

- `--connection-setup` 必须提供绝对路径的 `--data-directory` 与 `--connection-output`。目录须为空且不在生产资料树中；输出必须是该目录中的 JSON，拒绝与其他诊断混用。验证发生在构造 Store 和显示窗口之前。
- 不设置正常输入板、档案、菜单栏收音或快捷键入口。临时偏好强制从 `automaticRecovery=false` 启动；连接窗口中的自动恢复控件禁用。空独立库没有待处理录音。
- 完成出口只接受已应用且没有未保存更改的最高质量配置；五项核心服务、处理许可及 Keychain 属性存在性须通过。存在性不是密钥有效性或 API 联通性证明。
- 导出只编码 `RecognitionConfiguration`。使用无覆盖写入；已有配置不会被替换。未调用 `CloudCredentialStore.read`，未导出秘密。
- `ConnectionSetupTests`：4项原生测试通过，使用注入的合成“密钥存在”状态；无真实秘密访问。覆盖已有目录/越界输出拒绝、未应用/缺许可/缺密钥/缺核心角色拒绝、非秘密配置可解码与不可覆盖。
- `test-connection-setup.py`：7项真实开发构建的命令入口拒绝测试通过，无窗口、麦克风、数据库构造或服务请求。可对最终候选重复运行：

```sh
python3 scripts/test-connection-setup.py --app /ABSOLUTE/CANDIDATE/Saytile.app \
  --output research/asr/validation/rc2/connection-setup-cli-final.json
```

开发包已实际挂载此 SwiftUI 窗口并用原生 AXPress 验证未准备时“完成连接设置”不会导出或退出；未调用模型。真实密钥的交互式设置尚未执行，不能用模拟 Keychain 存在状态宣布服务已连接。
