#!/usr/bin/env bash
set -euo pipefail

# Build librime + dependencies for iOS and create xcframeworks.
# Both a simulator (SIMULATORARM64) and a device (OS64) slice are built so the
# resulting .xcframework binaries work for simulator runs AND device/ipa links.
# Usage:
#   ./scripts/build-librime.sh                                  # sim + device
#   PLATFORMS=SIMULATORARM64 ./scripts/build-librime.sh         # sim only
#   PLATFORMS=OS64           ./scripts/build-librime.sh         # device only

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIME_ROOT="${RIME_ROOT:-$ROOT/../librime}"
DEPS_DIR="$RIME_ROOT/deps"
BUILD_DIR="$ROOT/.build"
INSTALL_DIR="$BUILD_DIR/install"
FRAMEWORKS_DIR="$ROOT/Frameworks"

IOS_CMAKE_DIR="${IOS_CMAKE_DIR:-$BUILD_DIR/ios-cmake-4.6.0}"
IOS_CMAKE="$IOS_CMAKE_DIR/ios.toolchain.cmake"
PLATFORMS="${PLATFORMS:-SIMULATORARM64 OS64}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"

# 保留自定义工具链目录；默认缓存在项目内，重启后不必重新下载。
ensure_toolchain() {
  [[ -f "$IOS_CMAKE" ]] && return
  mkdir -p "$BUILD_DIR" "$IOS_CMAKE_DIR"
  local archive
  archive="$(mktemp "$BUILD_DIR/toolchain.XXXXXX")"
  trap 'rm -f "$archive"' EXIT
  curl --fail --location --retry 3 \
    "https://github.com/leetal/ios-cmake/archive/refs/tags/4.6.0.tar.gz" -o "$archive"
  tar -xzf "$archive" --strip-components=1 -C "$IOS_CMAKE_DIR"
  rm -f "$archive"
  trap - EXIT
  [[ -f "$IOS_CMAKE" ]] || { echo "error: missing $IOS_CMAKE" >&2; exit 1; }
}

export BOOST_ROOT="$DEPS_DIR/boost-1.89.0"

# Configure the per-platform variables used by every build_* function.
# Must be called once per platform at the top of a build iteration.
set_platform() {
  local p="$1"
  PLATFORM="$p"
  case "$p" in
    SIMULATORARM64)
      ARCH="arm64"
      SDK="iphonesimulator"
      MIN_FLAG="-mios-simulator-version-min"
      ;;
    OS64)
      ARCH="arm64"
      SDK="iphoneos"
      MIN_FLAG="-miphoneos-version-min"
      ;;
    *)
      echo "Unknown PLATFORM=$p"
      exit 1
      ;;
  esac

  SDK_PATH=$(xcrun --sdk "$SDK" --show-sdk-path)
  CMAKE_ARGS=(
    -DCMAKE_TOOLCHAIN_FILE="$IOS_CMAKE"
    -DPLATFORM="$p"
    -DDEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/$p"
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_SHARED_LIBS=OFF
  )

  mkdir -p "$INSTALL_DIR/$p/include" "$FRAMEWORKS_DIR"
}

build_boost() {
  echo "=== Building Boost for $PLATFORM ==="
  cd "$BOOST_ROOT"
  if [[ ! -f b2 ]]; then
    ./bootstrap.sh --with-toolset=clang --with-libraries=filesystem,regex,atomic
  fi

  # Build only the libs we need; header-only parts (incl. system since 1.82) are used directly.
  # -a forces a rebuild: b2's incremental key does not include cxxflags, so an
  # OS64 build would otherwise reuse the simulator build's object files.
  ./b2 -a -q \
    --with-filesystem --with-regex --with-atomic \
    toolset=darwin \
    target-os=iphone \
    architecture=arm \
    address-model=64 \
    cxxflags="-arch $ARCH $MIN_FLAG=$DEPLOYMENT_TARGET -isysroot $SDK_PATH" \
    link=static \
    variant=release \
    threading=multi \
    --stagedir="stage-$PLATFORM" \
    stage

  mkdir -p "$INSTALL_DIR/$PLATFORM/lib"
  cp "stage-$PLATFORM/lib/libboost_"*.a "$INSTALL_DIR/$PLATFORM/lib/"
  cp -R "$BOOST_ROOT/boost" "$INSTALL_DIR/$PLATFORM/include/"
}

build_dep() {
  local name="$1"
  shift
  cmake -S "$DEPS_DIR/$name" -B "$BUILD_DIR/$name-$PLATFORM" "${CMAKE_ARGS[@]}" "$@"
  cmake --build "$BUILD_DIR/$name-$PLATFORM" --target install -j"$(sysctl -n hw.ncpu)"
}

build_librime() {
  echo "=== Building librime for $PLATFORM ==="
  SRC="$RIME_ROOT"
  BUILD="$BUILD_DIR/librime-$PLATFORM"
  cmake -S "$SRC" -B "$BUILD" "${CMAKE_ARGS[@]}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC=ON \
    -DBUILD_MERGED_PLUGINS=ON \
    -DENABLE_EXTERNAL_PLUGINS=OFF \
    -DBUILD_TEST=OFF \
    -DBUILD_TOOLS=OFF \
    -DBOOST_ROOT="$BOOST_ROOT" \
    -DBoost_NO_BOOST_CMAKE=TRUE \
    -DCMAKE_PREFIX_PATH="$INSTALL_DIR/$PLATFORM" \
    -DCMAKE_FIND_ROOT_PATH="$INSTALL_DIR/$PLATFORM"
  cmake --build "$BUILD" --target install -j"$(sysctl -n hw.ncpu)"
}

make_xcframework() {
  local name=$1
  local lib=$2
  local output="$FRAMEWORKS_DIR/$name.xcframework"

  local staged_output="$BUILD_DIR/$name.xcframework"
  rm -rf "$staged_output"

  if [[ -d "$INSTALL_DIR/SIMULATORARM64/lib/$lib" || -f "$INSTALL_DIR/SIMULATORARM64/lib/$lib" ]]; then
    local sim_lib="$INSTALL_DIR/SIMULATORARM64/lib/$lib"
  else
    local sim_lib=""
  fi
  if [[ -d "$INSTALL_DIR/OS64/lib/$lib" || -f "$INSTALL_DIR/OS64/lib/$lib" ]]; then
    local dev_lib="$INSTALL_DIR/OS64/lib/$lib"
  else
    local dev_lib=""
  fi

  local args=()
  if [[ -n "$sim_lib" ]]; then
    args+=(-library "$sim_lib")
  fi
  if [[ -n "$dev_lib" ]]; then
    args+=(-library "$dev_lib")
  fi

  [[ ${#args[@]} -gt 0 ]] || { echo "error: no slices for $name" >&2; return 1; }
  xcodebuild -create-xcframework "${args[@]}" -output "$staged_output"
  rm -rf "$output"
  mv "$staged_output" "$output"
}

case "${1:-}" in
  ""|--package-only) ;;
  *) echo "usage: $0 [--package-only]" >&2; exit 2 ;;
esac

"$ROOT/scripts/verify-dependencies.sh" --sources

if [[ "${1:-}" != --package-only ]]; then
  ensure_toolchain
  for PLATFORM in $PLATFORMS; do
    set_platform "$PLATFORM"
    echo "=== Building for $PLATFORM ($SDK, arch $ARCH) ==="

    build_boost
    build_dep glog -DWITH_GFLAGS=OFF -DBUILD_TESTING=OFF -DWITH_GTEST=OFF
    build_dep leveldb -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF -DHAVE_CRC32C=OFF -DHAVE_SNAPPY=OFF -DHAVE_TCMALLOC=OFF
    build_dep marisa-trie -DENABLE_TOOLS=OFF -DBUILD_TESTING=OFF
    build_dep opencc -DUSE_SYSTEM_MARISA=OFF -DSHARE_INSTALL_PREFIX=SharedSupport -DBUILD_DOCUMENTATION=OFF -DENABLE_GTEST=OFF -DBUILD_OPENCC_TOOLS=OFF -DBUILD_OPENCC_DATA=OFF
    build_dep yaml-cpp -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF
    build_librime
  done
fi

# Package. make_xcframework picks up whatever slices exist in INSTALL_DIR, so it
# runs once after all platforms have been built.
make_xcframework librime     librime.a
make_xcframework libglog     libglog.a
make_xcframework libleveldb  libleveldb.a
make_xcframework libmarisa   libmarisa.a
make_xcframework libopencc   libopencc.a
make_xcframework libyaml-cpp libyaml-cpp.a
make_xcframework boost_filesystem libboost_filesystem.a
make_xcframework boost_regex    libboost_regex.a
# boost_system is header-only since Boost 1.82; no separate library.
make_xcframework boost_atomic   libboost_atomic.a

"$ROOT/scripts/verify-dependencies.sh" --record
echo "=== Done. Frameworks in $FRAMEWORKS_DIR ==="
