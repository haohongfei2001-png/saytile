# PR #4 融合质量修复验证

2026-11-06；起始远端HEAD `214ddb07d997231a3dce179c16cd7def1a055470`。旧候选 `f2ecf3a` 的204项测试不冒充当前结果。当前源码将在本目录交付清单记录精确SHA；先有源码提交，再构建未安装候选。RC1/main不变，不合并生产。

## 本机证据

- `native-final.log`：252 tests / 25 suites PASS，macOS27/Swift6.4 CLT；包含原有204项以及新增融合/事务/协调器/审计/诊断回归。
- `app-model-final.log`：21项真实AppModel独立资料库检查PASS；无麦克风、无外部输入、不激活窗口。
- `contract-verification.json` / `contract-tests.log`：继承契约与Swift6接口/Unicode smoke通过；不是实际云或UI验收。
- `publication-tests.log` 41项、`arbiter-tests.log` 27项、`store-final.log` 78项为开发时相交筛选，不能和252相加。`coordinator-audit-final.log`为9个协调器测试（两个参数化各2例）。
- `access-preflight.json`：仅Saytile专用Keychain元数据、禁止交互，0匹配；无保存云配置；未请求秘密值/没有上传和收费调用。
- `corpus-audit.json`：112条既有公共人声832.1804375秒，全部存在且哈希匹配。没有读取其他项目的资料或真人环境。

## 失败与根因保留

- `publication-before.log` / `meta-timing-before.log`：短复核漏后半句与Meta progress错误声学资格。
- `revision-before.log`：未派发全文/后缀被误当不可更正前缀。
- `coordinator-concurrent-before.log`：首轮241项全量的1项失败；并发双专家同时返回时旧状态触发不必要仲裁。后续current-snapshot调度与Store已接受决定缓存修复；最终252通过。
- `failure-before.log` / `failure-hold-before.log`：独立旧静态产物确实复现必需专家失败后仍能reserve旧结果；`failure-after.log` / `failure-hold-after.log`为同场景修复后NONE。
- `independent-review.log`：后到声学冲突使旧双专家proposal不能重新获得派发资格；仅保留亲自运行的事实，不编造其修前red。
- 新审计测试初稿曾错误要求所有稳定文字为空；真实共同前缀“支付”合法，修正测试要求该前缀保留且不派发争议数字/越界选择。这是纠正测试预期，未放宽生产证据校验。

## 质量与测量边界

真实云请求、跨服务准确率/延迟和收益全部NOT_RUN。输出是provider-decoded候选文本/token和decoded仲裁response审计，不声称完整HTTP/wire抓包。被校验拒绝的decoded仲裁回复也保留在modelUsage.arbitrationResponse，通过runID关联验证失败；缺usage不填0。HTTP失败/不完整无法decode回复只记安全错误与未知计费，不能当完整raw结果。

四阶段评分程序与11配置计划在 `../../benchmark/quality-evaluation/`：26项Python测试，全部112×3旧本地结果重新计分但明确legacy；四阶段时间和身份校验由5项Swift诊断测试覆盖。没有人工词时间或语义幻觉标签时明确null，不用自动对齐假冒gold。

当前[裁决](../../../../docs/ASR-FUSION-QUALITY-VERDICT.md)：无法给出“双专家+AI比最强单模型准多少/确认增加多少”的数字。仅支持工程缺陷已复现并修复。逐服务授权、费用与下一步均集中在评估目录，无需用户录音/调试。

## 最终候选与远端

源码提交 `1c907f63585183ad605140630d1ca979694fb2ea`，tree `f6d99665e091c178b04dfee1099f89aa3b2081c0`。它与本机测试提交87395e6的整个源码树完全一致；Git网络TLS失败后经GitHub connector创建树并核对精确SHA，再快速前进PR分支。没有force push；已按服务端原始Git元数据重建并验证commit哈希，把本地分支对齐远端。备份本地原提交保留在codex/fusion-quality-local-source。

该源码macOS26 CI252项/25组、21AppModel、原生窗口合成渲染、构建与隔离启动全部PASS；设计契约CI也PASS。链接和App artifact ID见delivery-manifest.json。只新增26项离线评分的Ubuntu CI步骤，不调用模型、不上传音频。

本机候选sourceDirty=false，版本1.0.0-asr-preview.2，release/signature/smoke PASS。未安装；App及ZIP保留在本持久工作树dist/。第一候选焦点测试PASS；改为远端同树源码身份重打包后一次探针出现frontmost_changed，该次未归因，不能断言用户操作或App抢焦点。随后仅一次附带候选PID归因的3秒复测PASS，候选从未成为前台、其他应用切换为0；所有日志保留，不把未归因记录删掉或作为长期无干扰保证。没有读取其他应用内容。
