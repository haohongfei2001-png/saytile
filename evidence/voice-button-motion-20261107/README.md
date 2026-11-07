# 语音按钮局部动效｜原设计保持不变

本次仅调整原语音胶囊内部的三种图形与短过渡。原紫蓝玻璃面板仍是设计依据；此目录不是新的完整界面设计稿。

![按钮内部动效演示](voice-button-motion.gif)

预览来自生产 `VoiceCaptureGlyphShape` 的 macOS 原生离屏渲染，使用合成幅度与采样形变参数。为让 GIF 正确显示半透明图层，导出时使用白色观察底色；这不修改产品材质或配色。循环仅方便查看，产品的暂停三角与待命圆点保持静止。

## 实现与验证身份

- 实现提交：[455143310222c2c03c4a4888e5df5552c3af4131](https://github.com/haohongfei2001-png/saytile/commit/455143310222c2c03c4a4888e5df5552c3af4131)。本轮界面仅替换 `Views.swift` 的内部语音图形，保留父提交 `1c81843` 的其他改动。
- 实际CI检出：`63a61ae3d33f8b871f3d0235d35ea130df4cbdc7`；已核对与实现提交拥有相同tree `87015ba6c1cb2b38c5a868a2fed1b86b9eaac683`，源码无未提交变更。
- [macOS原生CI 42331341272](https://github.com/haohongfei2001-png/saytile/actions/runs/42331341272) 与 [设计契约CI 42331341221](https://github.com/haohongfei2001-png/saytile/actions/runs/42331341221) 均通过。
- 392项Swift测试、48个套件、104项AppModel检查通过；27张既有原生窗口截图及新增71张按钮路径采样图完成。
- 新增检查覆盖有限且闭合的24×18图形边界、右向三角、稳定圆点、五根圆头竖条、真实幅度输入改变条高、无效幅度安全处理及过渡采样。暂停／待命不受音量值驱动。
- 本次CI未执行实际AX按键、未使用真实麦克风；采样图不是实际动画计时测试，也不代表完整面板通过用户视觉验收。

## 附件与复现

`native-motion-manifest.json` 为CI原始逐帧参数与时长记录；71个原生源帧经GIF编码合并相邻相同帧后为65帧，总预览时长仍为4.94秒。`native-ci-summary.log` 保存关键原始日志行。

在macOS构建后运行现有 `scripts/test-native-ui.py --app dist/Saytile.app --output <隔离输出目录>` 可重新生成 `voice-glyph-motion/` 原始PNG与manifest。生产按钮数据来自当前麦克风幅度；预览中的合成幅度仅用于确定性检查，不进入正常应用路径。

- 原生UI artifact ID：`13557806414`。
- 原始ZIP SHA-256：`f11254c1ee812ccd5d1b1be01a6a412cf5c34814395cab1b9ec1698b31705825`。
- 受测二进制 SHA-256：`79d792469795c17c2cf0775b087e8452290f9d8a9ef2241989aa28262423ed3b`。
- GIF SHA-256：`1727341b036040b5f351dbb29df00f31d763233c996394094f57645d49d66438`。
