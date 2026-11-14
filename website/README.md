# Saytile 正式官网

**当前版本：R8 已认可整体 + 2026-11-14 用户批准的两段新设计。** 正式入口：https://saytile.com/

本轮直接更新正式首页，不是新增预览。Header/Hero、R8 连续表达及原位核对、深色结尾保持；复制流程与语音档案两段重新实现为清晰的网页文字和交互，不将概念图贴成页面。

## 运行结构

样式：styles.css、panel.css、middle.css、scenes.css。脚本顺序：panel.js、hero.js、middle.js、scenes.js。旧 app.js 不再被根首页加载。15个当前运行文件的摘要见 SHA256SUMS.txt 和 snapshot.json。

复制段展示口述接续、停止、指针点击复制、移到 AI 输入框、粘贴并保留待发送草稿。自动演示不写剪贴板、不发送消息；只有用户手动点击复制才请求写剪贴板。示例粘贴不读取用户剪贴板。

档案提供搜索、筛选、记录选择、文字编辑、版本切换及音频回听。修改仅保留在当前页面会话。4段音频为明确标注的系统 TTS 合成示例，不是用户录音。生成参考里的云同步承诺没有当前发布依据，官网没有写成已上线功能。

## 运行与部署

在仓库根目录执行 `python3 -m http.server 8080 --directory website`。纯静态，无构建、外部字体或付费API。main 的 website/ 变动由 GitHub Pages 自动发布。

[批准范围](APPROVAL.md) · [本轮验证](VALIDATION.md) · [完整页面实拍](reference/full-page.jpg)

原R3批准和摘要在reference/history/；旧预览保留追溯。官网与原生App分别管理。
