> 已验证的875f66f检查点。后续并行上游安全修复与engine.single-transcript.2候选另行验收，不能将以下旧包身份/计数套用到新源码。

# Saytile 双专家单一文字流：核心工程候选交付

**ENGINE_CANDIDATE_VALIDATED / LIVE_ACCEPTANCE_PENDING。** 代码、构建和隔离工程验收已交付；不是已测得最高识别准确率或可直接替换RC1的正式版本。

代码源：`875f66fef52c10eac0e927512c9bb726f43d8e4c`。独立[工程PR #6](https://github.com/haohongfei2001-png/saytile/pull/6)叠加在已同步的[PR #5](https://github.com/haohongfei2001-png/saytile/pull/5)上。PR4/PR5/PR6均未合并main，已安装RC1/生产资料未改。

## 实际实现

两个平等实时ASR接收完整同PCM，不设主模型或语言预切；一个GPT WebSocket会话持续合并候选、校验版本、恢复上下文缓存，收尾强制最后评审。ASR临时预览与可派发文字分离，未经GPT认可的共识不自动认证为可输入。没有第二AI复听链；用户只看一份文字，内部保留证据，用户稿不能被后台覆盖。

Apple结果已进入统一Candidate/Store；云ASR连接失败后取消并等待旧会话退出，以新ticket从持久化PCM分块接替，跟随落盘尾部。Apple不可用则排队；授权/配额错误停止自动云重试，后续段按有界退避恢复云资格。GPT单独失败不触发这条Apple切换，而保留原有失败恢复机制。

PCM读取按真实样本范围跨块，单次内存上限1MiB，不再依赖12MB整段缓存。13.44MB合成范围回归已经验证，但不是24小时连续功耗验收。

外部修正已真实接入生产Store、协调器、AX适配与AppModel：只对最新仍可证明拥有的精确UTF-16范围局部替换；先持久化预留、再比较目标和原文，保护用户前后缀、编辑与emoji字素。范围变动、目标/页面/焦点改变、未确认投递或不支持原生setter时保留pending，不重复追加、不整框重写、不发送/回车。只能追踪最新可证明范围，不能任意移动旧段。AX没有跨进程原子CAS，原生兼容性仍需实测。

数据库增量升级到schema4，保留原始插入账本，区分单调插入坐标与已纠正的有效前缀；长短修正后都只追加后续新文字。重启使所有权失效、未知修正不重放。

## 实际验证

| 范围 | 结果 |
|---|---|
| 完整Mac原生与相同树CI | 313/313，37组，无跳过 |
| AppModel | 23/23 |
| 新配对评分 / 既有评分 | 20/20 与43/43 |
| 真实子进程SIGKILL、迁移、事务与删除恢复 | 12/12，独立合成资料 |
| 发布RC1包→候选包升级、旧版拒绝新库、独立备份恢复 | 8/8，仅临时安装副本 |
| 真实原生界面渲染 | 15张通过；未运行AX控件点击 |
| 云探针CLI /连接设置CLI隔离 | 4/4 与7/7；无云请求 |
| Release构建、ad-hoc签名、ZIP/DMG校验、隔离启动 | 通过 |
| GitHub native / design contracts | 均SUCCESS |

[原生CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42286973119) · [契约CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42286973120) · [机器回执](final/RECEIPT.json)。UI记录了一次外部前台变化且未归因，候选未激活；这不冒充真实目标应用修正验收。

## 候选身份

版本`1.0.0-engine.single-transcript.1`，Apple Silicon/macOS26+，ad-hoc签名，未公证、未替换已安装RC1。

[CI候选包](https://github.com/haohongfei2001-png/saytile/actions/runs/42286973119/artifacts/13538281787)的bundle内嵌GitHub测试合并提交`38c98a13bf04deb9ed9e4057788019a2cecb70c3`；与工程头`875f66f`的Git tree完全相同：`a2f94d97e81424ceec283fd111389a0634fee0b0`，不是另一个源码版本。下载的内层App ZIP SHA256为`0d6e374fbeb303137a56d08afee250bc92aad6517db4431365678b713019f001`。CI artifact保留至2026-11-20 20:20:34 UTC。

Mac另有同源码Release DMG，SHA256 `1005cf0ad834f8b36ff97c1a9f56d432dd1a204e66d8373a7343a0e6c69d97bd`。新库schema4不能让RC1直接读取；已验证基于停止态备份的隔离回退，但没有对生产库执行升级或回退。

## 真实准确率没有冒充完成

现有112真人音频全部核验，冻结24条（中/英/混说各8）核验通过；336条Apple/本地Qwen历史记录身份核验。A–E的120条计划和评分入口已准备，指标未运行时保持null，不用历史输出/合成fixture当云实测。

本轮Saytile专用Keychain元数据为0匹配项，且无生产云配置；因此A–E没有真实调用。Qwen Message+AssemblyAI是工程起始候选，未宣称最终准确率冠军；Soniox仍为挑战者。GPT-6 Astra官方不支持原生音频，因此F为NOT_AVAILABLE。当前不能量化GPT修正收益、引入错误或最终延迟。

仍需真实服务鉴权/协议/24条质量对照、真实Apple/麦克风输入、ChatGPT/Codex等目标的AX兼容性以及长时墙钟功耗验收。这些不是由CI替代的结论。未要求用户录音、标注或操作故障复现。

## 历史失败与修复

PR5旧native回归失败、集成时重复GPT fixture、原生UI仍期待已退休Gemini阶段/模式控件等都已修复并保留来源。早期Codex沙箱Keychain/静音播放失败不当作通过；父流程最终在Mac宿主完整313项不跳过通过。新增跨功能用例验证“外部缩短纠正→本地候选接替→只追加后缀”，避免独立模块单测通过但组合破坏账本。

本次后续提交仅补充验收记录；上述候选和全部运行日志固定属于875f66f及同树CI合并提交，不重标旧二进制来源。
