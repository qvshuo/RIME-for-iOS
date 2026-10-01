#!/usr/bin/env bash
set -euo pipefail

# Generate bundled data with a host librime build, keeping deployment out of the extension.
# Uses ../librime; run ./scripts/build-prebuilt-data.sh after schema changes.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIME_ROOT="${RIME_ROOT:-$ROOT/../librime}"
DEPS_DIR="$RIME_ROOT/deps"
BUILD_DIR="$ROOT/.build-host"
INSTALL_DIR="$BUILD_DIR/install"
SHARED_SUPPORT="$ROOT/Resources/SharedSupport"

export BOOST_ROOT="$DEPS_DIR/boost-1.89.0"

mkdir -p "$INSTALL_DIR/include"

HOST_CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"
)

build_boost() {
  echo "=== Building host Boost ==="
  cd "$BOOST_ROOT"
  if [[ ! -f b2 ]]; then
    ./bootstrap.sh --with-toolset=clang --with-libraries=filesystem,regex,atomic
  fi
  ./b2 -q \
    --with-filesystem --with-regex --with-atomic \
    toolset=clang \
    link=static \
    variant=release \
    threading=multi \
    --stagedir="stage-host" \
    stage
  mkdir -p "$INSTALL_DIR/lib"
  cp "stage-host/lib/libboost_"*.a "$INSTALL_DIR/lib/"
  cp -R "$BOOST_ROOT/boost" "$INSTALL_DIR/include/"
}

build_dep() {
  local name=$1
  local src="$DEPS_DIR/$name"
  local bdir="$BUILD_DIR/$name-host"
  shift
  echo "=== Building host $name ==="
  cmake -S "$src" -B "$bdir" "${HOST_CMAKE_ARGS[@]}" "$@"
  cmake --build "$bdir" --target install -j"$(sysctl -n hw.ncpu)"
}

build_librime() {
  echo "=== Building host librime (with rime_deployer) ==="
  local bdir="$BUILD_DIR/librime-host"
  cmake -S "$RIME_ROOT" -B "$bdir" "${HOST_CMAKE_ARGS[@]}" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_STATIC=ON \
    -DBUILD_MERGED_PLUGINS=ON \
    -DENABLE_EXTERNAL_PLUGINS=OFF \
    -DBUILD_TEST=OFF \
    -DBOOST_ROOT="$BOOST_ROOT" \
    -DBoost_NO_BOOST_CMAKE=TRUE \
    -DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
    -DCMAKE_FIND_ROOT_PATH="$INSTALL_DIR"
  cmake --build "$bdir" --target rime_deployer -j"$(sysctl -n hw.ncpu)"
}

deploy() {
  echo "=== Deploying prebuilt data ==="
  local stage previous
  stage="$(mktemp -d "$BUILD_DIR/deploy.XXXXXX")"
  previous="$stage/previous-build"
  # 两次重命名之间收到退出信号时，也要把旧数据放回原位置。
  trap 'if [[ -d "$previous" && ! -d "$SHARED_SUPPORT/build" ]]; then mv "$previous" "$SHARED_SUPPORT/build"; fi; rm -rf "$stage"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  local dep_path="$BUILD_DIR/librime-host/bin/rime_deployer"
  mkdir -p "$stage/shared" "$stage/user"
  # 不带旧 build，避免部署器误判为增量完成；失败时仍保留原来的预编译数据。
  tar -C "$SHARED_SUPPORT" --exclude=./build -cf - . | tar -C "$stage/shared" -xf -
  "$dep_path" --build "$stage/user" "$stage/shared"
  test -s "$stage/user/build/luna_pinyin_extended.prism.bin"
  test -s "$stage/user/build/luna_pinyin_extended.table.bin"
  test -s "$stage/user/build/melt_eng.table.bin"
  if [[ -d "$SHARED_SUPPORT/build" ]]; then mv "$SHARED_SUPPORT/build" "$previous"; fi
  if ! mv "$stage/user/build" "$SHARED_SUPPORT/build"; then
    if [[ -d "$previous" ]]; then mv "$previous" "$SHARED_SUPPORT/build"; fi
    return 1
  fi
  rm -rf "$previous" "$stage"
  trap - EXIT INT TERM
  echo "=== Prebuilt data written to $SHARED_SUPPORT/build ==="
}

case "${1:-}" in
  "")
    build_boost
    build_dep glog -DWITH_GFLAGS=OFF -DBUILD_TESTING=OFF -DWITH_GTEST=OFF
    build_dep leveldb -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF -DBUILD_SHARED_LIBS=OFF -DHAVE_CRC32C=OFF -DHAVE_SNAPPY=OFF -DHAVE_TCMALLOC=OFF
    build_dep marisa-trie -DBUILD_SHARED_LIBS=OFF -DENABLE_TOOLS=OFF -DBUILD_TESTING=OFF
    build_dep opencc -DBUILD_SHARED_LIBS=OFF -DUSE_SYSTEM_MARISA=OFF -DBUILD_DOCUMENTATION=OFF -DENABLE_GTEST=OFF -DBUILD_OPENCC_TOOLS=OFF -DBUILD_OPENCC_DATA=OFF
    build_dep yaml-cpp -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DBUILD_SHARED_LIBS=OFF
    build_librime
    ;;
  --deploy-only) ;;
  *) echo "usage: $0 [--deploy-only]" >&2; exit 2 ;;
esac
deploy
echo "=== Done ==="
