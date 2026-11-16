#!/bin/bash
set -euo pipefail
pkg=$1
rev=$2
stage=$3
vol=$(mktemp -d /private/tmp/saytile-mandarin-volume.XXXXXX)
[[ ! -e "$stage" && -f "$pkg" ]]
hdiutil verify "$pkg" >/dev/null
hdiutil attach -readonly -noautoopen -nobrowse -mountpoint "$vol" "$pkg" >/dev/null
trap 'hdiutil detach "$vol" >/dev/null' EXIT
a="$vol/Saytile 中文识别候选.app"
codesign --verify --deep --strict "$a"
[[ "$(plutil -extract SaytileSourceRevision raw "$a/Contents/Info.plist")" == "$rev" ]]
[[ "$(plutil -extract SaytileSourceDirty raw "$a/Contents/Info.plist")" == false ]]
mkdir "$stage"
ditto "$a" "$stage/Saytile 中文识别候选.app"
codesign --verify --deep --strict "$stage/Saytile 中文识别候选.app"
