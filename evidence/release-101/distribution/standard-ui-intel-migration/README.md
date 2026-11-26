# 标准 Sparkle UI 迁移到既有 Intel job

基线：`de45b0fb3c83e1fa13b6067a47b0342772e309ed`。仅迁移测试，不改变产品、签名 feed fixture 或已保留的失败原件。`standard-ui-ci-9a01841/` 的 sandbox 失败和主任务已取得的 `standard-ui-ci-de45b0f/` ARM 容量取消仍是各自原始结果。

`swift-tests` 继续使用现有 `macos-26-intel` runner。标准弹窗步骤在原 protocol 全套测试之后，复用 `/tmp/saytile-no-api-protocol-swift`，补建静态 `SaytileKit`，由 `prepare-updater.sh` 获取摘要固定的 Sparkle 2.10.1。没有新增 job、runner、重跑或部署。原 native 其余 21 个步骤、foreground job 和 protocol 步骤逐项保持一致。

编译 target 只接受 macOS `arm64`、`x86_64`。Python 收据写出编译 target 与架构，Swift 收据写出实际编译架构；CI 结果必须一致。版本号、完整 notes、SDK 默认 Install/Later 按钮、可见且激活的窗口、真实 Later 动作、关闭后控制器可用，以及 loopback-only 网络规则全部保留。Intel UI PASS 不能证明 Apple Silicon 推理或完整 App UI。

## 本轮实际验证

- **PASS**：`preflight.json`，工作流 YAML 解析、既有步骤保留、两个受支持 target 与三个拒绝案例、本机 UI 运行拒绝（exit 2）。
- **PASS（编译）**：`arm64-compile/build.log`，本机使用既有 release101 静态库与固定 Sparkle，Swift 6／warnings-as-errors 编译通过。该目录 `receipt.json` 的 UI 状态仍为 **NOT_RUN**，`compile_only=true`，没有启动 App、申请窗口激活或调用模型。
- **NOT_RUN**：Intel 编译与实际标准弹窗交互。由主任务统一推送后查看 `Saytile-standard-update-ui` artifact，不以本机 arm64 编译替代。
- **BLOCKED（只读状态刷新）**：本轮 git/gh 经规定局部代理读取远端遇到 SSL/EOF，GitHub connector 也出现 transport error；使用主任务交接的已推送基线，不冒称新的远端查询成功。没有触发 CI。

## 下一步

主任务统一推送并跟进原有 CI。独立 Intel 桌面必须产出实际 screenshot、native receipt 和总体 PASS，才可将标准弹窗结论从 NOT_RUN 更新。最终 575 包的真实升级、模型缓存与归档验收仍由另一组独立收据绑定，不复用 574 成功结论。
