# 隔离工程验收 · 2026-11-06

本目录保留最终实现源码 `f2ecf3ad84a0e5302ff0266bde3a72e9f3ba5163` 的实际工程结果。后续仅修改文档或归档证据，不把候选包的源码身份改写成文档提交。此前 `1204d95` 的 199 项结果保留于 Git 历史；此处是修复边界后重新执行的结果。

| 验证 | 观察结果 | 证据 |
|---|---|---|
| Mac Swift 原生测试 | 204 项 / 21 组通过 | `native-tests-macos.log` |
| 原生 AppModel | 21 项通过；无麦克风、外部输入或窗口激活 | `app-model-macos.log` |
| Release 构建、签名校验、plist | 通过 | `release-build-macos.log` |
| 原生 SwiftUI 渲染 | 11 个界面；前台不变；合成数据 | `ui-render-macos.log`、`ui-manifest-macos.json` |
| 启动检查 | 空隔离数据目录启动通过 | `startup-smoke-macos.log` |
| 继承设计契约 | PCM/SQLite 与 37 项重建契约通过 | `design-validation-linux.json`、`rebuilt-contracts-linux.log` |
| GitHub 原生 / 设计工作流 | 两者通过 | `candidate-identity.json` 中 run ID |
| DMG | 生成成功，`hdiutil verify` 通过 | `package-macos.log`、`candidate-identity.json` 中 SHA-256 |

`ai-services.png` 和 `ai-chinese-keychain.png` 来自真实生产 SwiftUI 组件的隔离渲染，其哈希与本次 UI manifest 一致。它们不是设计稿。AX 控件点击未运行，不能用截图成功替代控件交互验收。

没有真实云调用或费用；没有新的 CER/WER/MER、四阶段延迟或融合收益数据。上述结果验证代码、恢复与发布边界，不能证明云端识别质量。原有 Apple/Qwen 实测不变，生产 RC1、用户原音、私人数据库未作为试验对象。

[原生 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42228489112) · [设计 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42228489455) · [候选 App 下载](https://github.com/haohongfei2001-png/saytile/actions/runs/42228489112/artifacts/13507371027)

Actions 候选包为临时工程产物，当前过期时间见身份文件；没有发布正式 Release 或替换生产安装。
