# 1.0.1（577）最终更新与归档验收

本目录绑定实际 Developer ID 签名包 `/private/tmp/saytile-release101-577/Saytile.app`，产品源码 `3e1cc6961df4da01a1c52310755a7dd215ef4310`，主可执行文件 SHA-256 `34c7ec7da5cb483aaa702f38e7ff69e1125a4d1352f3256392413541277f1e48`。实际 App 测试在主任务明确发出 `ASRdone` 后顺序执行；575、576 原始结果全部保留。

**本次存储、更新和归档检查 PASS；公开发行未执行。** 完整 CI、其他产品验收、公证与 Gatekeeper 裁决由主任务汇总，已有公证授权阻断没有因此消失。

## 新 Kit 输入的存储回归

576→577 产品修改仅为 `InputAccessibility.swift` 的页面上下文 AX 传输错误分类及 `BUILD_NUMBER`。ASR、存储和更新源码未变，但整个 SaytileKit 输入树已不同；原完整输入树校验正确拒绝旧 576 storage receipt，结果保留于 `old-storage-binding-rejection.json`。没有放宽脚本或重写旧结果。

原样运行 `scripts/test-rc-storage-processes.py --deny-network`，在 `/private/tmp/saytile-release101-577-storage` 重新编译当前 Kit/probe 与已发布 Beta/RC1 存储 probe。**18 项全部 PASS**，包括真实 SIGKILL、原音/修订持久性、崩溃恢复、磁盘写失败原子性、旧 schema 升级和显式回退。实际测试 HEAD 与产品冻结 SHA 完全相同；新 probe SHA-256 `78d867166f52529b09a85957add91b112b92b744dfbf713c9e5d57920ba676a2`，原完整输入树校验通过。

## 一次真实 572→577 更新与缓存检查

`release-model-cache/receipt.json`：**PASS**。原样复用 `test-release-update.py`，真实 1.0.0（572）→1.0.1（577）安装成功；坏包被 Sparkle 4005 拒绝，目标离线打开、当前版本不重复安装、旧 572 重新打开同一隔离资料均通过。只在不执行的比较副本去除签名来核对代码字节，实际运行/安装副本始终保持并验证 Developer ID 签名。

两条合成录音、四份文字修订、手工编辑、草稿、段落和未确认派发资料前后摘要相同。授权研究 Qwen 权重 APFS clone 到隔离缓存：**6 文件、712,777,119 字节**，升级及回退后全部 SHA-256、修改时间和研究源本身不变。没有下载或加载模型，没有访问生产缓存。

## 一次实际原生 host 安装与重启

`native-update/receipt.json`：**PASS**。实际 577 host/controller 经 Sparkle installer 完成退出保存、安装、无参数重启和后继 PID 验证，完整资料、偏好及缓存 canary 保留。既有夹具的版本 aliases 为 1→2，与上方真实 572→577 分别报告。

有效签名说明进入展示回调；篡改说明被 2001／3002 拒绝且不展示；坏包被 4005 拒绝。使用既有 deterministic driver 和禁止激活路径，没有在本机显示标准 Sparkle 弹窗，没有执行可选线上空 feed 或设置 AX 检查。

## 最终原身份 ZIP/feed

未修改的 `distribution/create-update.py` 通过已有账户内部调用准备待发布文件，状态 `PREPARED_NOT_PUBLISHED`。原公钥、身份与生产 feed 不变，没有生成或导出密钥。

- ZIP：`/private/tmp/saytile-release101-577-update-prepared/Saytile-1.0.1-update.zip`，**55,581,018 字节**，SHA-256 `7cc3dcf91e28082e7a3f74b35f1fa504e691d0235f17e4e883ab113c4f7a2854`。
- Feed：同目录 `appcast.xml`，SHA-256 `bdc63d4d657be4e2ed16aea188cdbe84160329dcc9903c6af502240eab886ddb`；内联纯文字说明逐字对应本目录既有 1.0.1 说明快照。
- 原 archive 公钥校验与 Sparkle feed 校验 PASS。另以 `verify-public-signatures.py` 和已有 CryptoKit verifier，使用已发布公钥对整个 ZIP 及 feed 明确长度覆盖的原始 payload **分别独立验签 PASS**；该复核不访问 Keychain、不调用签名工具。
- `verify-prepared.py`、`verify-public-signatures.py` 仅将 576 常量改为 577，其他断言不变。解包 **136 个文件/链接、67 个目录 mode** 与最终签名 App 完全一致；deep/strict codesign、Developer ID、hardened runtime、时间戳均通过。未启动或注册解包副本，未移除 quarantine。

ZIP 留在上述独立交付目录，不进入 Git，未覆盖 `dist`、正式更新源或历史版本。未来 release URL 不代表文件已发布；后续公证、装订或重签名后须重新生成 ZIP/feed 与摘要。

## 边界

未操作用户安装 533、生产资料/录音/缓存，未运行 ASR、付费 API、可见标准 UI、上传、发布、合并、公证或更改 Gatekeeper。固定 574 标准弹窗 signed feed 的字节和摘要保持不变；其 CI 结论由主任务独立保存，不冒充本轮本机验收。原始收据、日志、复现输入、逐项解包 manifest 和验签脚本完整保留；总摘要见 `summary.json`。

原始产品 diff 中两条空行上下文只含 Git 的单空格前缀，普通 `git diff --check` 因此报告 trailing whitespace。原件与两源码 SHA 的 `git diff` 输出逐字节相同，未为格式检查修改原始证据；其余提交文件检查通过，详情见 `commit-format-check.json`。
