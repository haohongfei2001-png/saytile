## 2026-11-16 · 0.19 外观与反馈工程收口

唯一产品源码 `412d008be30471abf7cf89e99ee7d4c10ae6cb92`，0.19（500）；PR47保持该已测SHA，本次分支仅补交付证据。完整CI 5/5 PASS，Swift Testing 548/548、XCTest 30/30、AppModel 188/188、反馈controller 12/12；最终签名包13项反馈原生检查、8项外观检查及0.18→0.19→0.18→0.19合成资料回退通过。修复测试确认框UNKNOWN判断及宿主激活，未放宽安全条件。 [完整收据、截图与限制](../evidence/feedback-019-final/README.md)。

真实反馈服务仍BLOCKED：需要已有Cloudflare账户一次Wrangler登录，随后由工程迁移/部署及验证真实私有Issue送达；当前并未接通。签名包未公证、未安装，现用0.18与受保护App/私人资料保持。无主板改版、ASR变更、付费调用、main合并或公开发布。

# Saytile V1 工程交付状态

最新独立开发为0.15自然段候选，基于已安装0.14（478）源码`7fd9296d8eb2bd81379bbaa7287844d0d46703d5`。主板与档案统一15秒自然段、默认60秒时间组；原音与历史版本保留。实现、独立审查及原生窗口回归完成，最终同源CI/签名包收据另行追加。[自然段交付说明](NATURAL-PARAGRAPHS.md)。以下旧版本说明保留为历史记录。

个人内测原版为 Saytile.app（0.12）。中文识别独立候选为 0.13（466），使用自己的档案和设置。[最终签名候选的原速对照和实测](../evidence/mandarin-preview-20261114/DELIVERY.md)。最新源码、原生体验证据与实际限制见[当前开发状态](V1-DEV-STATUS.md)及[逐版本实测记录](V1-TEST-RESULTS.md)；下述冻结候选记录独立保留。

独立 Draft PR #12 的时间轴预览使用源码 86dbd24。新包与 RC2 并存。[预览交付和机器收据](V1-CONTINUOUS-TIMELINE.md)

冻结 RC2 工程候选 `1.0.0-rc.2-no-api.10`，源码 `5639058e6b178027861b18cc0521387487c919d5`。核心状态为 `READY_FOR_AUTHORIZED_API_ACCEPTANCE`。完整实机验收与公开分发仍为 BLOCKED。真实云端 NOT_RUN。生产 main、RC1 和 no-api.9.1 保留原版本。

[封版报告和唯一安装包](V1-NO-API-DELIVERY.md) · [逐项证据](../evidence/no-api10/final/machine.json) · [授权事项](V1-USER-ACTIONS.md)


2026-11-10 · 独立商业候选（未发布）：见 [Saytile Cloud 交付与阻塞](SAYTILE-CLOUD-DELIVERY.md)。线上网关存在；付费托管及公开分发尚未开放。

2026-11-10 · 独立本机 ASR 候选 [签名包与 M5 机器验收](V1-LOCAL-ASR-ACCEPTANCE.md)。三种真流式、一种分块、三种归档；仅 Draft PR #15，不取代任何冻结版本。
