#!/bin/bash
set -Eeuo pipefail
trap 'printf "LOCAL_RUNTIME_FAILURE prepare-local-runtime.sh line=%s exit=%s pipeline=%s\n" "$LINENO" "$?" "${PIPESTATUS[*]}" >&2' ERR
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
# Reconstruct both upstream inputs before applying local patches; no dependency
# on a previously prepared (possibly different) working tree.
original=$(mktemp -d)
trap 'rm -rf "$original"' EXIT
mkdir -p "$original/Sources/Qwen3ASR"
for source in Qwen3ASR.swift QuantizedTextDecoder.swift; do
  git -C "$cache/speech-swift" show "$speech:Sources/Qwen3ASR/$source" > "$original/Sources/Qwen3ASR/$source"
done
patch -s -f -p1 -d "$original" < "$pkg/qwen-verified-preview.patch"
patch -s -f -p1 -d "$original" < "$pkg/qwen-compiled-decoder.patch"
for source in Qwen3ASR.swift QuantizedTextDecoder.swift; do
  cmp -s "$original/Sources/Qwen3ASR/$source" "$pkg/.vendor/SpeechKernels/Sources/Qwen3ASR/$source" || cp "$original/Sources/Qwen3ASR/$source" "$pkg/.vendor/SpeechKernels/Sources/Qwen3ASR/$source"
done
cmp -s "$pkg/SpeechKernels.swift-manifest" "$pkg/.vendor/SpeechKernels/Package.swift" || cp "$pkg/SpeechKernels.swift-manifest" "$pkg/.vendor/SpeechKernels/Package.swift"
mkdir -p "$pkg/.vendor/FluidAudio"
if [[ ! -f "$pkg/.vendor/FluidAudio/.$fluid" ]]; then
  git -C "$cache/FluidAudio" archive "$fluid" | tar xf - -C "$pkg/.vendor/FluidAudio"
  touch "$pkg/.vendor/FluidAudio/.$fluid"
fi
