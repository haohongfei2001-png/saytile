# 1.0.1（576）最终更新与归档验收

本目录绑定实际 Developer ID 签名包 `/private/tmp/saytile-release101-576/Saytile.app`，产品源码 `2d12129f2031fdf827d51fa1796d155e79243e07`，主可执行文件 SHA-256 `037bb2de64765458cecd9288a09969d3e733345040a9a95e1e286b98b988536c`。主任务确认签名包构建完成后开始，所有测试顺序执行；575 原始结果全部保留。

**本次存储、更新和归档检查 PASS；公开发行未执行。** 标准弹窗 CI、其他产品验收、公证与 Gatekeeper 裁决由主任务汇总，已有公证授权阻断没有因此消失。

## 存储来源闭环

575→576 产品修改仅为 `InputAccessibility.swift` 的 AXRole 保守分类及 `BUILD_NUMBER`。ASR、存储和更新源码未变，但整个 SaytileKit 输入树已不同；旧 storage receipt 被原严格校验正确拒绝，结果保存于 `old-storage-binding-rejection.json`，没有放宽脚本或重写旧结果。

随后原样运行 `scripts/test-rc-storage-processes.py --deny-network`，在独立 `/private/tmp/saytile-release101-576-storage` 重新编译 SaytileKit、当前 probe 与已发布 Beta/RC1 的存储 probe。**18 项全部 PASS**：包括真实子进程 SIGKILL、原音/修订持久性、崩溃恢复、磁盘写失败原子性、旧版 schema 升级与显式回退。真实测试 HEAD 为 `27e758662ec00708d56ae063561aaec0dc578b74`，新 probe SHA-256 `2e712cc983d2fe7c454faf16c504853f77227b38a07424abbb0a964d21dd6754`；原校验确认完整 storage/probe 输入树与产品源码完全一致。

## 一次真实版本安装与缓存检查

`release-model-cache/receipt.json`：**PASS**。原样复用 `test-release-update.py`，真实 1.0.0（572）→1.0.1（576）一次安装成功；损坏 archive 被 Sparkle 4005 拒绝，目标可离线打开，当前版本不重复安装，旧 572 可重新打开同一隔离资料。比较不执行的去签名副本来核对代码字节，实际安装副本始终保持并验证 Developer ID 签名。

两条合成录音、四份文字修订、手工编辑、草稿、段落与未确认派发资料前后摘要相同。授权研究 Qwen 权重 APFS clone 到隔离缓存：**6 文件、712,777,119 字节**，升级和回退后的所有 SHA-256、修改时间及研究源本身不变。未下载或加载模型，没有访问生产缓存。

## 一次实际原生 host 安装与重启

`native-update/receipt.json`：**PASS**。实际 576 host/controller 经 Sparkle installer 完成退出保存、安装、无参数重启、后继 PID 与资料/偏好保留；该既有夹具版本 aliases 为 1→2，与上方真实 572→576 分别报告。

签名说明实际进入展示回调，篡改说明被 2001／3002 拒绝且不展示；坏包被 4005 拒绝。使用既有 deterministic driver 与禁止激活路径，没有在本机显示默认标准弹窗；没有执行可选线上空 feed 或设置 AX 检查。

## 原身份 ZIP、feed 与独立验签

使用未修改的 `distribution/create-update.py` 和已有 Sparkle 账户生成待发布文件，状态为 `PREPARED_NOT_PUBLISHED`，不生成/导出密钥，不修改公开 feed。

- ZIP：`/private/tmp/saytile-release101-576-update-prepared/Saytile-1.0.1-update.zip`，**55,578,054 字节**，SHA-256 `9c9aaf38958e9b33b5e0838e3894f678c3b8c67fd85d148eefc083279eadb080`。
- Feed：同目录 `appcast.xml`，SHA-256 `5fbe8913628ef8cd7242fd6f6d53a8441f3c8729f33ee658da8e72a2c8cc2d66`。内联纯文字说明逐字绑定本目录的主任务说明快照。
- 原脚本的 archive 公钥校验及 Sparkle feed 校验均 PASS。另用 `verify-public-signatures.py` 提取 feed 明确长度覆盖的 1,930 字节原始 payload，调用既有 CryptoKit Ed25519 verifier，**ZIP 与 feed 分别以已发布公钥独立验签 PASS**；这一步不调用签名工具或 Keychain。
- `verify-prepared.py` 只把原 575 版本常量改为 576，其他断言不变。解包后 **136 个文件/符号链接、67 个目录 mode** 与签名原 App 逐项相等，`codesign --verify --deep --strict` PASS，Developer ID/hardened runtime/时间戳存在。未启动解包副本、未注册 Launch Services、未删除 quarantine。

ZIP 保留临时交付目录，不进入 Git。未来 release URL 不是已发布证明；任何后续公证、装订或重签名都须重新生成 ZIP/feed 与摘要。

## 边界

生产安装 0.20（533）、用户资料/录音/缓存没有访问；未运行 ASR、付费 API、公开上传、发布、合并、公证或更改 Gatekeeper。固定 574 标准 UI signed feed 摘要原样保持，未拿新 feed 改写既有 CI 夹具。原始收据、运行日志、复现输入、解包 manifest 和公开验签脚本均在本目录；总摘要见 `summary.json`。
