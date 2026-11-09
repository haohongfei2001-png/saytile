## RC2 连续时间轴整合候选

独立分支继承 PR #12，恢复正式应用、偏好、档案与 Keychain 身份。已修复编辑期间空白面板复制旧组、午夜归日取整两项实测缺陷。发布继续等待真实云端和公证。[独立终审](V1-RC2-TIMELINE-INTEGRATION.md)

# 连续时间轴独立预览

独立 Draft PR #12 已实现跨日期分页、空闲留白、原文就地修订与选区复制。签名预览使用独立资料目录。 [完整交付及验收](V1-CONTINUOUS-TIMELINE.md)

# no-api.10 开发状态

冻结产品源码为 `5639058e6b178027861b18cc0521387487c919d5`。PR #10 的后续提交保存安装包、实验驱动和收据。生产 main、RC1 和 no-api.9.1 独立保留。

- 录音开始时固定一个已核验的 ASR，GPT-6 仅处理候选文字。Auto 缺少讲话语言证据时使用本机识别。改动模型、授权或凭据会使原有连接回执失效。
- WKWebView 的原生写入可在实际成功后返回超时。派发器只执行一次写入，再读取并比对受限范围及前后文字。所有权、窗口、焦点或内容发生变化即停止修改，未确认投递在重启后不会自动重放。
- 修正原生设置诊断替身对未选模型的凭据要求。实际安全字段、菜单、成功、失败和取消路径已在签名 App 上核验。真实云端保持 NOT_RUN。

[最终交付](V1-NO-API-DELIVERY.md) · [业务源码](../Sources) · [逐项机器收据](../evidence/no-api10/final/)


2026-11-10 · Saytile Cloud: Independent cloud candidate: gateway and transactions implemented; native integration follows.
