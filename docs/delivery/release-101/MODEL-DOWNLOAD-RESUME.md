# 1.0.1 真实 HTTPS 模型断点恢复

结论：**PASS（64 KiB 断点恢复及重复下载范围）**。不是完整 713 MB 下载速度测试，也不是 ASR 质量测试。

## 固定产品与输入

- 产品源码：`73ad857442964437929819ba9965f6bcfdcefd27`，Saytile 1.0.1（574）。
- 使用该候选现成的 Release `libSaytileKit.a`，调用正式 `LocalModelLibrary.download` / `status`；未重编或修改产品。
- 模型：`aufklarer/Qwen3-ASR-0.6B-MLX-4bit`，固定 revision `bc441bd1e4295c1f42d9879f056049a925b6e013`，原六文件 manifest 完全不变。
- 输入为授权研究缓存的 APFS clone。先核对原六文件 SHA-256，然后只将隔离副本的 `model.safetensors` 截去末尾 65,536 字节。没有访问用户生产缓存。
- 单线程 utility 读取文件做哈希；轻量 probe 运行 nice 20。没有加载 ASR、打开麦克风或重编完整产品。

## 实际结果

测试时间：2026-11-24 18:21:03–18:21:11 UTC。

| 检查 | 结果 |
| --- | --- |
| 未完整 partial 不得启用 | PASS，恢复前 `installed=false` |
| 真实源与传输 | 1 个 URLSession 任务，`huggingface.co` 302 → `us.aws.cdn.hf.co` 206 |
| Range | `bytes=708171409-708236944` |
| CDN Content-Range | `bytes 708171409-708236944/708236945` |
| 应用实际补回文件数据 | 65,536 字节；正式库验证响应体大小与 Content-Range |
| URLSession 正文传输统计 | 66,664 字节：302 响应 1,074；206 响应 65,590（传输编码口径，不与落盘 payload 混淆） |
| 恢复操作时间 | 2.771 秒，包含正式库的文件完整性校验，不作为纯网络吞吐成绩 |
| 六文件恢复后 SHA-256 | 全部与原 manifest 一致，总大小 712,777,119 字节 |
| 全新库实例验证 | PASS；重新创建 `LocalModelLibrary`，不沿用下载对象的校验缓存 |
| 重复 download | PASS；URLSession 新建任务数保持 1，无额外网络任务 |
| 研究源完整性 | PASS，前后六文件摘要完全一致 |
| 异常整包响应保护 | 配置超过 64 KiB 的响应取消；此次未触发，服务器正确返回范围响应 |

`evidence/release-101/model-resume-real/source.json` 记录冻结产品文件、完整 manifest、链接 Release 静态库与实际 probe 的 SHA-256。`receipt.json` 保留每个文件的长度/摘要、全部网络任务的无敏感参数指标及时间。CDN 签名 URL 的查询参数不记录、不提交。

没有修改系统代理、网络连接或 TLS 校验。使用真实 URLSession 和当前系统网络配置，没有 mock、备用源或改写 manifest。

## 前置失败与限制

最初两个 probe 在联网前被自身路径保护拒绝：macOS Foundation 将**已经存在**的 `/private/tmp/...` 规范化成 `/tmp/...`，但未创建的目标路径仍保留 `/private/tmp/...`。通过直接路径实验确认后，改为验证规范化后的已存在父目录与专用 basename；没有放宽到生产缓存路径。两次的网络任务数均为 0，尚未读取或克隆模型；收据中的 `sourceVerified=false` / `sourceUnchanged=false` 表示未到验证阶段，不表示模型发生变化。

两份原始前置失败保存在 `model-resume/`、`model-resume-canonical/`。首轮沙箱禁止降低调度优先级的日志也保留；实际成功运行位于授权原生环境，使用 nice 20。

本次 PASS 覆盖**已有部分文件后的真实断点续传、完整校验、缓存复用**。未进行系统断网切换、传输中关机、完整首次下载、模型推理或真实麦克风测试。没有把这些项目声明为通过。

## 复现

```sh
scripts/test-model-download-resume.sh \
  /private/tmp/saytile-release-101 \
  /private/tmp/saytile-release101-release-build/out/Products/Release \
  /private/tmp/saytile-beta-021-20261123/.build/local-asr/weights/qwen-small/bc441bd1e4295c1f42d9879f056049a925b6e013 \
  /private/tmp/saytile-resume-new-evidence \
  73ad857442964437929819ba9965f6bcfdcefd27
```

必须使用全新的输出目录。脚本拒绝源码或 manifest 与冻结 SHA 不符；probe 拒绝生产缓存和已存在目标目录。成功后的隔离模型副本留在收据中的专用 `/private/tmp/saytile-model-resume-*` 路径，便于复核；不安装到产品缓存。
