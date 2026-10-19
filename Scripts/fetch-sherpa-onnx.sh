#!/bin/bash
# Собирает SherpaOnnx.xcframework из готовой сборки sherpa-onnx (Apache-2.0) для Apple Silicon.
#
# Бинарники (~100 МБ) в git не кладём: скрипт скачивает их с релиза k2-fsa/sherpa-onnx,
# проверяет контрольные суммы и склеивает в один фреймворк. Запускать один раз перед первой сборкой
# (см. CLAUDE.md, «Первый запуск»). Повторный запуск ничего не делает, если фреймворк уже есть.
set -euo pipefail

VERSION="1.13.8"
LIB_SHA256="3d7f9b8a496694af13d9802c33b8133231e397bdef302f543d19468765e83136"
HEADER_SHA256="2a1b95084be8fd1deb3228fcad2fd3f7f0258b64582f7402281ec174c7b7f4ce"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/NotesSpeech/Vendor/SherpaOnnx.xcframework"
if [ -d "$DEST" ]; then
  echo "уже есть: $DEST"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
NAME="sherpa-onnx-v$VERSION-osx-arm64-static-no-tts-lib"

echo "качаю sherpa-onnx $VERSION…"
curl -fsSL -o "$TMP/lib.tar.bz2" "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$VERSION/$NAME.tar.bz2"
echo "$LIB_SHA256  $TMP/lib.tar.bz2" | shasum -a 256 -c -
curl -fsSL -o "$TMP/c-api.h" "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v$VERSION/sherpa-onnx/c-api/c-api.h"
echo "$HEADER_SHA256  $TMP/c-api.h" | shasum -a 256 -c -

tar xjf "$TMP/lib.tar.bz2" -C "$TMP"
# portaudio (запись звука) и C++ API нам не нужны: звук пишет AVAudioEngine, вызываем через C API.
LIBS=$(ls "$TMP/$NAME/lib/"*.a | grep -v -e portaudio -e cxx-api)
libtool -static -o "$TMP/libsherpa-onnx.a" $LIBS 2>/dev/null

mkdir -p "$TMP/include"
cp "$TMP/c-api.h" "$TMP/include/"
cat > "$TMP/include/module.modulemap" <<'MAP'
module SherpaOnnxC {
    header "c-api.h"
    export *
}
MAP

mkdir -p "$(dirname "$DEST")"
xcodebuild -create-xcframework -library "$TMP/libsherpa-onnx.a" -headers "$TMP/include" -output "$DEST" >/dev/null
echo "готово: $DEST"
