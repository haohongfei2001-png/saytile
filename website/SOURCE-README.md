# Saytile 官网 · 第三版

面向中文用户的 Saytile 产品官网。静态 HTML、CSS、JavaScript，无构建依赖；`dist/` 为完整部署目录。

## 产品主线

自然说下去，眼前始终是一份持续核对、忠实于原话的文字。常驻、连续表达、原音保存和文字取用围绕这一核心组织。

首屏以原生语音板为唯一产品主角。第二屏直接演绎语气、补充与同一处的细微修订；第三屏用连续时间轴展示停顿后的延续与回看；随后交代复制和原音，最后提供真实内测入口。

## 视觉与动效

- 近白底色、深墨正文、正式品牌紫，细节保持中性白灰。
- 一块白色微透玻璃板，无标题、无产品名；底部仅复制和语音按钮。
- 紫色三角 / 圆点 / 五根圆头竖条对应暂停、继续聆听、讲话。讲话结束回圆点。
- 语块渐入、局部文字修订、时间轴追加与回看、轻微指针视差；动画一次完成，支持 reduced-motion。
- 删除前版的假 AI 对话应用与阅读器、双份文字同步、播放进度条和大段操作说明。
- 正式图标沿用原始文件，SHA-256：`607fe0dca53a186835a35e82b0c9241975e11b9e3481e6dfb11502fe60d5f35c`。

## 文件

- `dist/index.html`：页面与示例内容。
- `dist/styles.css`、`dist/app.js`：整页布局、动效、连续时间轴。
- `dist/panel.css`、`dist/panel.js`：独立的原生语音板组件与交互。
- `dist/assets/saytile-approved.webp`：正式应用图标。

## 功能与范围

语音板可暂停、继续、明确重播、编辑和复制；真实编辑受到保护，自动动画不会覆盖它。复制默认当前文字，有选区则复制选区。连续时间轴可追加示例句子和回看。

页面明确标注为产品交互演示。示例不调用麦克风或 ASR，不伪装真实语音识别质量；时间轴为演示数据，不是实际档案 UI。原生窗口默认几何以产品仓库为准，网页呈现为局部放大。iCloud 尚未取得实现证据，因此未列为已交付能力。

## 依据

已核查 `haohongfei2001-png/saytile`，PR #23，固定 SHA `3c59273fac988cde4b883b0d4d21f7a3f74f747d`。

- https://github.com/haohongfei2001-png/saytile/blob/3c59273fac988cde4b883b0d4d21f7a3f74f747d/docs/01-PRODUCT-AND-ROADMAP.md
- https://github.com/haohongfei2001-png/saytile/blob/3c59273fac988cde4b883b0d4d21f7a3f74f747d/docs/PRODUCT-DECISIONS-2026-11-09.md
- https://github.com/haohongfei2001-png/saytile/blob/3c59273fac988cde4b883b0d4d21f7a3f74f747d/design/approved/Saytile-original-visual-reference-20261107.jpeg
- https://github.com/haohongfei2001-png/saytile/pull/23

## 托管

沿用既有 Sites 项目与访问范围，`.openai/hosting.json` 指向 `dist/`。不改变原生产品仓库或发行包。
