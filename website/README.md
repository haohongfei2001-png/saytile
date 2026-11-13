# Saytile 正式官网

**当前正式版本：2026-11-13 用户批准的 R3。**

完整、可运行的官网就在本目录。运行文件从已发布版本逐字节复制，保留 HTML、CSS、JavaScript、动效、响应式布局和正式图标；本次没有重新制作或简化页面。

- [版本批准与保留细节](APPROVAL.md)
- [冻结文件与 SHA-256](snapshot.json)
- [运行文件校验清单](SHA256SUMS.txt)
- [实际验证记录](VALIDATION.md)
- [原设计说明](SOURCE-README.md)
- [首屏截图](reference/desktop-hero.jpg) · [完整页面截图](reference/full-page.jpg)
- [当前线上预览](https://saytile-voice-20261113.dark-koala-7130.chatgpt.site/)（保留原访问范围）

## 本地运行

在仓库根目录运行：

```sh
python3 -m http.server 8080 --directory website
```

随后打开 http://localhost:8080 。复制按钮需要浏览器允许的安全上下文；localhost 可以使用。正式托管请使用 HTTPS。

## 部署

直接把本目录作为静态网站根目录即可，无 npm 安装、构建命令、后端、运行时 API 或外部 CDN 依赖。必需文件共 6 个：

| 文件 | 作用 |
| --- | --- |
| index.html | 全部页面结构、文案、语义标签与内联 SVG |
| styles.css | 页面排版、环境光、响应式与整页动效 |
| app.js | 首屏配合、局部修订、时间轴、重播与提示 |
| panel.css | 语音板材质、尺寸、按钮、光标及状态动效 |
| panel.js | 语音演示、暂停/继续、编辑保护、复制 |
| assets/saytile-approved.webp | 用户批准的正式图标 |

保持相对路径不变，并保持 `panel.js` 在 `app.js` 前加载，两个脚本均使用 `defer`。本目录已包含需要发布的全部资源，不需要从截图重建，也不要只复制 `index.html`。

本次没有迁移域名或改变线上访问设置。HTML 的 `og:url` 原样保留已发布地址；未来绑定正式域名时可单独更新该元数据，不应借此改写页面。

## 校验

在本目录运行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

六项全部通过，表示运行文件与批准版本逐字节相同。截图是 Chromium 的实际渲染参考；网站使用系统字体，不同系统字体渲染可能不同。

## 产品范围

这是官网与产品交互演示，语音过程不访问麦克风、不调用 ASR；时间轴使用示例内容。它不会替代原生 App 的 UI 权威、产品状态或真实语音验收。

源版本：Sites commit `3bf7ceea971f0b97543daa6d9893671562d52489`。用户已明确要求把此版写入本 GitHub 仓库作为正式官网。
