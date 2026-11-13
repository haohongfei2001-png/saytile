#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pkg=native/LocalASR
cache=.build/local-asr
mkdir -p "$cache" "$pkg/.vendor/SpeechKernels/Sources"
checkout() {
  local repo=$1 path=$2 revision=$3
  if [[ ! -d "$path/.git" ]]; then
    git init -q "$path"
    git -C "$path" remote add origin "https://github.com/$repo.git"
  fi
  if ! git -C "$path" cat-file -e "$revision^{commit}" 2>/dev/null; then git -C "$path" fetch -q --depth 1 origin "$revision"; fi
}
speech=a57702e6f523fa36ac5532d2bdc5f35f701a052c
fluid=653386fa4a8f7083ce669560b5bafd9ac54754a1
checkout soniqo/speech-swift "$cache/speech-swift" "$speech"
checkout FluidInference/FluidAudio "$cache/FluidAudio" "$fluid"
if [[ ! -f "$pkg/.vendor/SpeechKernels/.$speech" ]]; then
  git -C "$cache/speech-swift" archive "$speech" Sources/{AudioCommon,MLXCommon,SpeechVAD,Qwen3ASR,NemotronStreamingASR} LICENSE | tar xf - -C "$pkg/.vendor/SpeechKernels"
  touch "$pkg/.vendor/SpeechKernels/.$speech"
fi
# Start from the pinned blob on every preparation so edits to the patch and
# reused build directories produce the same source as a clean checkout.
qwen=Sources/Qwen3ASR/Qwen3ASR.swift
staged=$(mktemp -d)
trap 'rm -rf "$staged"' EXIT
mkdir -p "$staged/Sources/Qwen3ASR"
git -C "$cache/speech-swift" show "$speech:$qwen" > "$staged/$qwen"
echo "dd028981de6dcbeb5d0953efff60535e8dbff88c109d1b3fb10aadb60328b41f  $staged/$qwen" | shasum -a 256 -c - >/dev/null
patch -s -d "$staged" -p0 -i "$PWD/$pkg/QwenPreviewScratch.patch"
cmp -s "$staged/$qwen" "$pkg/.vendor/SpeechKernels/$qwen" || cp "$staged/$qwen" "$pkg/.vendor/SpeechKernels/$qwen"
cmp -s "$pkg/SpeechKernels.swift-manifest" "$pkg/.vendor/SpeechKernels/Package.swift" || cp "$pkg/SpeechKernels.swift-manifest" "$pkg/.vendor/SpeechKernels/Package.swift"
mkdir -p "$pkg/.vendor/FluidAudio"
if [[ ! -f "$pkg/.vendor/FluidAudio/.$fluid" ]]; then
  git -C "$cache/FluidAudio" archive "$fluid" | tar xf - -C "$pkg/.vendor/FluidAudio"
  touch "$pkg/.vendor/FluidAudio/.$fluid"
fi
