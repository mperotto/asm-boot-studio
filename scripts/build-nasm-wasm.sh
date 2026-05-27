#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-3.01}"
TARBALL_URL="https://www.nasm.us/pub/nasm/releasebuilds/${VERSION}/nasm-${VERSION}.tar.xz"
BUILD_DIR="${ROOT_DIR}/vendor/nasm-release"
OUT_DIR="${ROOT_DIR}/vendor/nasm-wasm"
ARCHIVE_PATH="${ROOT_DIR}/vendor/nasm-${VERSION}.tar.xz"

mkdir -p "${ROOT_DIR}/vendor" "${OUT_DIR}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

curl -L "${TARBALL_URL}" -o "${ARCHIVE_PATH}"
tar -xf "${ARCHIVE_PATH}" -C "${BUILD_DIR}" --strip-components=1

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "${ROOT_DIR}:/work" \
  -w /work/vendor/nasm-release \
  emscripten/emsdk:3.1.72 \
  bash -lc '
    rm -f config.log config.status Makefile nasm nasm.wasm
    emconfigure ./configure --host=wasm32-unknown-emscripten CC=emcc CFLAGS="-O2"
    emmake make nasm \
      LDFLAGS="-O2 -sENVIRONMENT=web,worker -sMODULARIZE=1 -sEXPORT_NAME=NasmModule -sALLOW_MEMORY_GROWTH=1 -sFILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=[\"FS\",\"callMain\"]" \
      -j2
  '

cp "${BUILD_DIR}/nasm" "${OUT_DIR}/nasm.js"
cp "${BUILD_DIR}/nasm.wasm" "${OUT_DIR}/nasm.wasm"
