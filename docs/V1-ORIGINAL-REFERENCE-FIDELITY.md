## Integrated reference-sized window correction

The prior `473d6ed` change and its design provenance are retained in history. This follow-on integrates the measured reference with the **actual shipping window**, not a separate presentation-only mockup:

- The card is 344 × 234 pt (688 × 468 reference pixels); its transparent 32 pt perimeter carries the native SwiftUI shadow. The outer NSPanel is therefore 408 × 298 pt, not a larger content card. It is borderless and nonactivating, with no added title bar or double system shadow.
- The footer has the source image's asymmetric optical insets: 20.5 pt leading, 14 pt trailing, 18 pt bottom. Copy is 42 × 33.5 pt; voice is 92.5 × 33.5 pt. The gray overlapping-square mark is retained, not recolored purple.
- The body uses native selectable PingFang SC Regular 19.5 pt with 26 pt line height. The reference fixture retains the source's visible line breaks; production text is never hard-coded. Trailing punctuation has optical whitespace rather than compressed Chinese punctuation. A noninteractive purple live caret uses the final glyph's ink bounds and disappears during selection or reading earlier text.
- Three new reference captures use `InputPanelWindowView`, also used by the actual AppDelegate. The standard 27/37 native render/control scenarios and the synthetic glyph geometry checks remain. VAD, ASR, storage, menus and cross-app dispatch are unchanged.

**唯一视觉原图：** [design/approved/Saytile-original-visual-reference-20261107.jpeg](../design/approved/Saytile-original-visual-reference-20261107.jpeg)（用户上传文件原字节，不是工程截图）。本文件所记录的原生几何和渲染证据必须以它作为上位标准；若出现冲突，原图优先。

Measurements and source identity: [`original-reference-20261107.measurements.json`](../design/approved/original-reference-20261107.measurements.json). This record must not be replaced by the dimensions of old gray or flat-gradient engineering captures. No desktop wallpaper is modified. No physical microphone or live cloud call is part of these synthetic UI checks. Literal original-pixel identity and user visual approval are not inferred from passing engineering tests.

---

# 原版视觉还原：以用户新上传图为准

用户再次否决此前“灰白卡片”和“给灰白卡片加紫色渐变”的近似实现。它们不是批准设计。原稿必须保留，不允许以原生实现方便或测试通过为由更换外观。

## 设计依据

本轮依据用户直接上传的完整 1536×1024 JPEG，SHA-256 为 `58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5`。这是本轮可读取的原始上传附件，不冒称取得更早图片的无损 PNG。附件没有私人桌面内容。完整 JPEG 原始字节现已原样存入 [唯一视觉原稿](../design/approved/Saytile-original-visual-reference-20261107.jpeg)，由 SHA-256 `58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5` 校验；它不等于更早的无损设计源文件。

主卡片在图中约为 690×469 像素，按 2× 映射到原生默认 345×234pt。测量存在 JPEG 抗锯齿和图形原稿本身的不确定性；不是对字体源文件或逐像素完全相同的声明。

| 部位 | 本轮按原图校准 |
|---|---|
| 主卡片 | 345×234pt；圆角28pt；左紫右蓝材质、细高光边 |
| 正文 | 19.5pt、26pt 行高；使用 PingFangSC-Regular 校准字宽，不改输入文字 |
| 文字起点 | 约22pt水平边距，包含原生文字视图自身2pt内边距 |
| 左下复制 | 42×34pt、灰色重叠圆角方框；不再用紫色折角文档图标 |
| 右下语音 | 92×34pt；保留紫色三角、圆点、圆头小竖条及可打断变形 |
| 控件底边 | 18pt；半透明填充、上缘高光、下方轻阴影 |
| 正文光标 | 讲话时原文末尾紫色标记；不接管焦点，不修改文字，选区存在时不绘制 |

## 不变的语义

未开启和手动暂停共用朝右三角；待命为静态圆点；只有真实当前讲话驱动圆头竖条。VAD确认声音结束回待命，后台定稿继续；点击才暂停。原稿的配色、相对比例、按钮方位和单一正文形式不是重新设计的自由项。

本轮没有更改 AppModel、音频、识别或存储代码。默认窗口尺寸依据原稿修正，用户已有窗口定位/缩放保留，不强制重置个人偏好。

## 校验与证据解释

原生 AppKit/SwiftUI 截图使用原图同一句合成文字，而不是用更短的例句掩盖字号和留白差异；自然换行由原生文字排版引擎计算，不通过人为换行伪造完全一致。

`original-reference/reference-paused.png`、`reference-standby.png`、`reference-speaking.png` 是真实原生视图的独立渲染。`reference-presentation.png` 在同一生产视图外增加仅用于评审的紫蓝底和示例投影，不是屏幕录制、不读取私人桌面、也不改变用户的壁纸；实际窗口仍使用系统窗口投影。

这次增加参照原图的度量和截图，不把旧色卡或单纯 CI 通过当作用户已接受外观。最终视觉是否符合原稿须如实依据对照；不宣称逐像素复刻。

初次直接运行 `swift test` 遇到本机 CLT 缺少自动加载 TestingMacros 的已知构建环境问题；改用仓库已有 `scripts/test-native.sh` 明确加载该宏库，不修改业务代码规避测试。完整原生渲染和几何结果以本轮保存的日志为准。
