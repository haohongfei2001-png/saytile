# 0.21 Release Closure

当前裁决：HOLD，工程进行中，不合并或公开发布。现用533与私人资料保持。

A 已完成：刷新远端main/PR49/50/51，PR51仍Draft且base为next-release-020；d6b54a6完整7项CI成功。核验563 DMG和现用533二进制哈希。来源见evidence/release-021/baseline.json。

B 离线两轮已完成，均FAIL：局部候选接续未降低2.549s原始到达间隔；禁止回退方案将停顿扩大到8.948–9.914s，均不进入产品。34份相同原始候选和逐条结果保存在evidence/release-021/publisher。保留563生产算法。最终源码构建后仍做三组原速压力配对与15段回归，不宣称算法/CPU改善。

C 已完成两轮诊断：五段均逐帧匹配完整公开语料，位于独立Apple识别正文时间范围外；Qwen原片段及诊断增益均为空。高度支持非语音触发，但无人听审，不伪称绝对静音；全部仍失败可重试。修正空EOS被误报为未收到定稿的文案，保留原音、候选与编辑。32项本地Swift Testing通过，最终SHA全套测试待D。详见evidence/release-021/empty-final。

D 进行中，0.21（564）准备最终产品SHA：最终产品SHA的420准确率、原生交互与浏览器、数据/更新回退、签名包和适用长测；硬件缺失NOT_RUN。

E 提前整理源码以使D的全部验收绑定发行分支：仅查现有公证授权；可用则真实公证/装订/Gatekeeper。基于最新main逐项选入正式产品及必要依赖，不机械合并历史。创建指向main的发行Draft PR并标明旧PR来源。官网/公开feed在放行前保持原版本。

iCloud与反馈暂不作为首个公开Beta绝对门槛，未就绪保持关闭，不宣称已同步或跨设备通过。最少账户动作统一在最后交付。

发行分支codex/release-021直接基于main 4caf73c；按产品/依赖/测试范围导入540个源文件，并非合并历史提交链。未导入5554项历史证据变化和旧DMG，官网保留main。构建号显式564，避免58次提交的新主线倒退到旧版本。Chrome/Edge/Safari扩展验收仅在隔离CI进行，不打开用户浏览器。

2026-11-23 阶段D中间收据：最终签名产品源码06997bd，564 DMG SHA-256 4c86d8cd7a29f7bce4682bf8fd994ab251e1d86f8914c38a470d96426eb13be7。Developer ID及时间戳PASS，App/DMG Gatekeeper均明确拒绝Unnotarized Developer ID；Keychain公证profile元数据0、Actions secrets 0，公证BLOCKED，不绕过。

完整Xcode CI首轮：568 Swift Testing（38+530）/30 XCTest全部通过；native作业成功。Chrome、Edge、TextEdit、AppKit/WKWebView通过；Safari测试页首次绑定前光标为0而非预期7，修复一次性隔离测试初始化，不重新夺焦、不改变产品约束。补回整理主线时遗漏的HostedPaused测试源。原始失败日志保留，等待修复后CI。

完整15段原速复验：46/568=8.10%，UI首字P95 1.499s、有效新字间隔P95 1.020s，15段全部讲话中更新。此前一次退出未留原生文件，保留原始运行日志且已修复验收器在失败前保存输出；不抹去该次异常。压力第一轮实际负载未达标准，原样保留，不算有效配对；第二轮有2组有效配对、第三组一侧负载不足，继续完成独立回归后补齐一次有效配对。不得据此宣称压力或CPU改善。
