## 2026-11-14 · 已交付内测0.15（484）自然段

产品源码 `ab8545507c79640ec3f419e33467a0263c154844`，Draft PR #41（基于PR #40），最终5/5 CI成功：524/524 Swift Testing、172项AppModel；最终签名包17项原生、12k时间轴/AX复制与478→484→478→484升级回退全部PASS。已在原路径更新并启动中文识别候选，正式App373及原有资料不被工程替换。

主板与档案同用15秒自然段/默认60秒时间组；短暂停顿继续同段，回听/收藏/编辑按整段。修复最终CI实际暴露的连接检查发送节拍漂移与首次Web写入AX短时不可读的过早失效；不重发、不抢焦点，不放宽所有权或完整证据规则。ASR运行库/模型/默认配置逐字节沿用478。

无需用户操作。麦克风按要求合盖NOT_RUN，云端API/新ASR评测NOT_RUN；未公证，独立分发Gatekeeper为BLOCKED。iCloud新段界恢复仍待独立PR整合。本轮不合并、不发布、不改变main。完整源码、DMG SHA-256、实际安装、截图、CI及失败历史见[最终机器收据](../evidence/natural-paragraphs/final/DELIVERY.md)。此文件在独立证据分支更新，不改变已签名产品SHA。

# Saytile V1 工程交付状态

最新独立开发为0.15自然段候选，基于已安装0.14（478）源码`7fd9296d8eb2bd81379bbaa7287844d0d46703d5`。主板与档案统一15秒自然段、默认60秒时间组；原音与历史版本保留。实现、独立审查及原生窗口回归完成，最终同源CI/签名包收据另行追加。[自然段交付说明](NATURAL-PARAGRAPHS.md)。以下旧版本说明保留为历史记录。

个人内测原版为 Saytile.app（0.12）。中文识别独立候选为 0.13（466），使用自己的档案和设置。[最终签名候选的原速对照和实测](../evidence/mandarin-preview-20261114/DELIVERY.md)。最新源码、原生体验证据与实际限制见[当前开发状态](V1-DEV-STATUS.md)及[逐版本实测记录](V1-TEST-RESULTS.md)；下述冻结候选记录独立保留。

独立 Draft PR #12 的时间轴预览使用源码 86dbd24。新包与 RC2 并存。[预览交付和机器收据](V1-CONTINUOUS-TIMELINE.md)

冻结 RC2 工程候选 `1.0.0-rc.2-no-api.10`，源码 `5639058e6b178027861b18cc0521387487c919d5`。核心状态为 `READY_FOR_AUTHORIZED_API_ACCEPTANCE`。完整实机验收与公开分发仍为 BLOCKED。真实云端 NOT_RUN。生产 main、RC1 和 no-api.9.1 保留原版本。

[封版报告和唯一安装包](V1-NO-API-DELIVERY.md) · [逐项证据](../evidence/no-api10/final/machine.json) · [授权事项](V1-USER-ACTIONS.md)


2026-11-10 · 独立商业候选（未发布）：见 [Saytile Cloud 交付与阻塞](SAYTILE-CLOUD-DELIVERY.md)。线上网关存在；付费托管及公开分发尚未开放。

2026-11-10 · 独立本机 ASR 候选 [签名包与 M5 机器验收](V1-LOCAL-ASR-ACCEPTANCE.md)。三种真流式、一种分块、三种归档；仅 Draft PR #15，不取代任何冻结版本。
