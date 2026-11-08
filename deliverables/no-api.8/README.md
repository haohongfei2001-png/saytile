> 固定色彩基准包，供源码和测试核对。PR #6 后续的中性玻璃修订尚未包含在这个发布二进制中。

# Saytile V1 RC2 · no-api.8

Apple Silicon / macOS 26+ 的工程候选。[确切运行源码 `69b90939`](https://github.com/haohongfei2001-png/saytile/commit/69b90939fd688b35448f976950e96db0ce5b602a)。按[上传原稿的实测几何](../../design/approved/original-reference-20261107.measurements.json)保留 344×234 pt 卡片和 408×298 pt 生产窗口。稳定 RC1 不变。

- [候选 DMG](Saytile-1.0.0-rc.2-no-api.8-arm64.dmg)，SHA-256 `c639ec375974b1a507041b6372724a42f119df802ce386ce11539674ada8cd6a`，大小 2,558,024 字节。
- 解包 App 可执行文件 SHA-256 `4b23cfba9b84da2538c449940d4694355c19d87a4aa66032b08e1893f9a9a2f7`。严格代码签名校验通过；ad-hoc，未 Developer ID 公证，本机[Gatekeeper 执行策略拒绝](../../evidence/no-api8/final/gatekeeper.json)。该工程包还不能作为面向普通下载用户的公开发行版。
- [安装、备份与回退](../../docs/V1-INSTALL.md) · [本版证据](../../evidence/no-api8/) · [云端连接入口](../../docs/V1-USER-ACTIONS.md)。

未调用真实云服务或上传私人录音。实际真人质量及相对最强单模型的收益未测。
