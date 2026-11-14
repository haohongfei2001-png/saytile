#!/bin/bash
set -euo pipefail
app='/private/tmp/saytile-response-final/Saytile 中文识别候选.app'
out='/Users/hhf/Documents/GitHub/saytile/dist/asr-response-0.16-486'
evidence='/private/tmp/saytile-response-evidence/evidence/asr-response-016'
sha=d0b2d87320fd4145fbaea756690066bca3718bab
identity=92B7E50A1D43D247EA7EA19A31DCA3E407435A42
mkdir -p "$out"
image="$out/Saytile-0.16-486-mandarin-arm64.dmg"
[[ ! -e "$image" ]]
[[ "$(plutil -extract SaytileSourceRevision raw "$app/Contents/Info.plist")" == "$sha" ]]
[[ "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" == 486 ]]
[[ "$(plutil -extract SaytileSourceDirty raw "$app/Contents/Info.plist")" == false ]]
codesign --verify --deep --strict "$app"
stage=$(mktemp -d /private/tmp/saytile-response-dmg.XXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Saytile 中文识别候选.app"
cat > "$stage/安装与使用.txt" <<'GUIDE'
Saytile 0.16（486）——独立识别可靠性候选

源码：d0b2d87320fd4145fbaea756690066bca3718bab
本包仅修复真实重复解码证据未送到文字发布器的问题。
原速对照未证明整体提速或降低 CPU；当前不自动替换已安装的 0.15（484）。
这是本地 Developer ID 签名工程候选，未提交 Apple 公证、未正式发布。
不要关闭 Gatekeeper 或改变系统安全设置；发行安装仍受公证条件限制。

工程回退测试只使用隔离合成资料，未读取或替换现有档案、录音、密钥及模型缓存。
本包继续使用 app.saytile.mac.mandarin-candidate，资料、设置和密钥服务与原中文候选一致，
与正式 app.saytile.mac 独立。不得同时启动两个具有同一候选身份的 App。
大型模型不在安装包内；现有已校验 Qwen 权重不会因本次更新自动重下载。
需要回退时退出候选，用已保留的 0.15（484）签名包恢复同一路径；不要删除资料目录。

本轮保持 Mac 合盖，不测试物理麦克风、不上传私人录音、不调用云端或收费服务。
完整结果与限制：GitHub Draft PR #42 及 codex/asr-response-016-evidence 分支。
GUIDE
hdiutil create -volname 'Saytile 0.16 (486)' -srcfolder "$stage" -format UDZO "$image"
codesign --force --timestamp --sign "$identity" "$image"
codesign --verify --strict "$image"
hdiutil verify "$image"
shasum -a 256 "$image" > "$out/SHA256SUMS.txt"
cp "$stage/安装与使用.txt" "$out/安装与回退说明.txt"
python3 /private/tmp/saytile-015-delivery/validate-image.py "$app" "$image" "$evidence/package.json"
cp "$evidence/package.json" "$out/package.json"
