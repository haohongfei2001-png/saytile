#!/bin/bash
# Build-time dependencies only. Installed applications execute bundled arm64 code.
set -euo pipefail
cd "$(dirname "$0")/.."
cache=.build/local-asr
runtime="$cache/runtime"
mkdir -p "$runtime"
fetch() {
  local url=$1 path=$2 checksum=$3
  if [[ ! -f "$path" ]] || [[ "$(shasum -a 256 "$path" | cut -d' ' -f1)" != "$checksum" ]]; then
    curl -fsSL --retry 2 --connect-timeout 15 "$url" -o "$path.part"
    echo "$checksum  $path.part" | shasum -a 256 -c -
    mv "$path.part" "$path"
  fi
}
sherpa=sherpa-onnx-v2.0.1-osx-arm64-shared-no-tts-lib
fetch "https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.1/$sherpa.tar.bz2" "$cache/sherpa.tar.bz2" ac5594ad237db56ec4a6c4b3fc48700441b33a07bb71c235f35530a52a93f2e3
fetch https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v2.0.1/sherpa-onnx/c-api/c-api.h "$cache/sherpa.h" 5698f38ba09ad2bdf085c56a6cbbd7741acf15e25f4ce5c7097b9702cadf437f
tar -xjf "$cache/sherpa.tar.bz2" -C "$cache"
cp "$cache/$sherpa/lib/"{libonnxruntime,libsherpa-onnx-c-api}.dylib "$runtime/"
clang++ -std=c++17 -O2 -fobjc-arc -mmacosx-version-min=26.0 -framework Foundation \
  -I"$cache" native/LocalASR/SherpaWorker.mm -L"$runtime" -lsherpa-onnx-c-api -Wl,-rpath,@executable_path -o "$runtime/SaytileSherpa"
scripts/prepare-local-runtime.sh
swift build --package-path native/LocalASR --build-system native --only-use-versions-from-resolved-file -c release --product SaytileModelWorker
cp native/LocalASR/.build/release/SaytileModelWorker "$runtime/"
# The matching MLX shader library is shipped by speech-swift's arm64 release.
fetch https://github.com/soniqo/speech-swift/releases/download/v0.0.29/speech-macos-arm64.tar.gz "$cache/speech.tar.gz" ff426a060004dd39b3d00ad014a648747d48cb78b800672aa17221ada2453406
tar -xzOf "$cache/speech.tar.gz" mlx.metallib > "$runtime/mlx.metallib"
licenses="$cache/runtime-licenses"
if [[ -d "$licenses" ]]; then chmod -R u+w "$licenses"; rm -rf "$licenses"; fi
mkdir -p "$licenses"
cp native/LocalASR/.vendor/SpeechKernels/LICENSE "$licenses/speech-swift.txt"
cp native/LocalASR/.vendor/FluidAudio/LICENSE "$licenses/FluidAudio.txt"
for lib in native/LocalASR/.build/checkouts/*; do
  for name in LICENSE LICENSE.txt LICENSE.md; do
    if [[ -f "$lib/$name" ]]; then cp "$lib/$name" "$licenses/$(basename "$lib").txt"; break; fi
  done
done
mkdir -p "$licenses/speech-components"
git -C "$cache/speech-swift" archive a57702e6f523fa36ac5532d2bdc5f35f701a052c ThirdPartyNotices | tar xf - -C "$licenses/speech-components"
cp -R native/LocalASR/Licenses/. "$licenses/"

