# Saytile 正式官网

**当前版本：R8 已认可整体 + 2026-11-14 用户批准的两段新设计。** 正式入口：https://saytile.com/

本轮直接更新正式首页，不是新增预览。Header/Hero、R8 连续表达及原位核对、深色结尾保持；复制流程与语音档案两段重新实现为清晰的网页文字和交互，不将概念图贴成页面。

## 运行结构

样式：styles.css、panel.css、middle.css、scenes.css。脚本顺序：panel.js、hero.js、middle.js、scenes.js。旧 app.js 不再被根首页加载。17个当前运行文件的摘要见 SHA256SUMS.txt 和 snapshot.json（包括 robots.txt 与 sitemap.xml）。

复制段展示口述接续、停止、指针点击复制、移到 AI 输入框、粘贴并保留待发送草稿。自动演示不写剪贴板、不发送消息；只有用户手动点击复制才请求写剪贴板。示例粘贴不读取用户剪贴板。

档案提供搜索、筛选、记录选择、文字编辑、版本切换及音频回听。修改仅保留在当前页面会话。4段音频为明确标注的系统 TTS 合成示例，不是用户录音。生成参考里的云同步承诺没有当前发布依据，官网没有写成已上线功能。

## 运行与部署

在仓库根目录执行 `python3 -m http.server 8080 --directory website`。纯静态，无构建、外部字体或付费API。main 的 website/ 变动由 GitHub Pages 自动发布。

[批准范围](APPROVAL.md) · [本轮验证](VALIDATION.md) · [完整页面实拍](reference/full-page.jpg)

原R3批准和摘要在reference/history/；旧预览保留追溯。官网与原生App分别管理。

## 1.0.0 正式下载更新

下载区已经上线正式 1.0.0（572），沿用已批准视觉，仅改入口、安装限制及版本说明。GitHub Pages部署、公开页面25项交互、15项资源摘要和实际点击下载完整DMG均已通过，见 VALIDATION.md 及仓库 evidence/release-100/publication/。签名已验证，尚未公证，明确说明 Gatekeeper 单 App 确认。原 0.18 安装包仍保留在 GitHub 历史 Release。

## 1.1.0 文案精修候选

本分支进一步明确「自然讲话 → 面板实时呈现 → 连续自然段 → 一键复制」、本地识别和历史表达；首次使用不需要账号、API Key、快捷键或外部输入位置。沿用现有布局、颜色、CSS、JS、演示和媒体。下载仍指向实际已发布的1.0.0；1.1.0安装包完成后再更新下载版本与安装信息。本分支的文案修改尚不代表线上已部署。
