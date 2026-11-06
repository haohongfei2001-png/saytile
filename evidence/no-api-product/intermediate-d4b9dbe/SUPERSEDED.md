# no-api.2 交付暂缓：确证可变音频块丢失

原测试与CI结果保留，不能抵消后续源波形对照发现的缺陷。长跑文件/数据库一致，但输入与保存内容在918.80375秒后出现缺口，末尾相对参考偏移1486个16kHz帧。短样本可变输入块复现：converter可先吐内部缓存且不调用inputBlock；旧CaptureWorker循环已取出ring新块却未保留它，导致丢音。ring dropped=0不覆盖这种应用层丢失。

本候选不是NO_API_ENGINEERING_READY，不应安装代替RC1。根因、红绿证据与修复见 ../audio-buffer-ownership/。新版no-api.3将重新完整验证。旧独立审计建议已被这项确证缺陷撤回，原始审计仅作当时证据的历史记录。
