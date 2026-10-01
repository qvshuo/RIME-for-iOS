#!/usr/bin/env bash
set -e

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

IOS_CMAKE_DIR="${IOS_CMAKE_DIR:-/tmp/ios-cmake-4.6.0}"
IOS_CMAKE="$IOS_CMAKE_DIR/ios.toolchain.cmake"
PLATFORMS="${PLATFORMS:-SIMULATORARM64 OS64}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"

# ios-cmake lives in /tmp by default, which the OS clears on reboot. Fetch it
# when missing instead of failing.
ensure_toolchain() {
  if [[ ! -f "$IOS_CMAKE" ]]; then
    echo "=== ios-cmake toolchain not found at $IOS_CMAKE; downloading ==="
    local tgz="/tmp/ios-cmake.tgz"
    curl -sfL "https://github.com/leetal/ios-cmake/archive/refs/tags/4.6.0.tar.gz" -o "$tgz" || {
      echo "error: failed to download ios-cmake 4.6.0" >&2
      exit 1
    }
    rm -rf "$IOS_CMAKE_DIR"
    tar -xzf "$tgz" -C /tmp
    [[ -f "$IOS_CMAKE" ]] || { echo "error: $IOS_CMAKE not produced by tarball" >&2; exit 1; }
  fi
}
ensure_toolchain

# Which deps to build
DEPS="glog leveldb marisa-trie opencc yaml-cpp"

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

  mkdir -p "$INSTALL_DIR/$p" "$FRAMEWORKS_DIR"
}

# ------------------------------------------------------------------
# 1. Boost
# ------------------------------------------------------------------
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
  cp -R "$BOOST_ROOT/boost" "$INSTALL_DIR/$PLATFORM/include/" 2>/dev/null || true
}

# ------------------------------------------------------------------
# 2. glog
# ------------------------------------------------------------------
build_glog() {
  echo "=== Building glog for $PLATFORM ==="
  SRC="$DEPS_DIR/glog"
  BUILD="$BUILD_DIR/glog-$PLATFORM"
  cmake -S "$SRC" -B "$BUILD" "${CMAKE_ARGS[@]}" \
    -DWITH_GFLAGS=OFF \
    -DBUILD_TESTING=OFF \
    -DWITH_GTEST=OFF
  cmake --build "$BUILD" --target install -j$(sysctl -n hw.ncpu)
}

# ------------------------------------------------------------------
# 3. leveldb
# ------------------------------------------------------------------
build_leveldb() {
  echo "=== Building leveldb for $PLATFORM ==="
  SRC="$DEPS_DIR/leveldb"
  BUILD="$BUILD_DIR/leveldb-$PLATFORM"
  cmake -S "$SRC" -B "$BUILD" "${CMAKE_ARGS[@]}" \
    -DLEVELDB_BUILD_TESTS=OFF \
    -DLEVELDB_BUILD_BENCHMARKS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DHAVE_CRC32C=OFF \
    -DHAVE_SNAPPY=OFF \
    -DHAVE_TCMALLOC=OFF
  cmake --build "$BUILD" --target install -j$(sysctl -n hw.ncpu)
}

# ------------------------------------------------------------------
# 4. marisa-trie
# ------------------------------------------------------------------
build_marisa() {
  echo "=== Building marisa-trie for $PLATFORM ==="
  SRC="$DEPS_DIR/marisa-trie"
  BUILD="$BUILD_DIR/marisa-$PLATFORM"
  cmake -S "$SRC" -B "$BUILD" "${CMAKE_ARGS[@]}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_TOOLS=OFF \
    -DBUILD_TESTING=OFF
  cmake --build "$BUILD" --target install -j$(sysctl -n hw.ncpu)
}

# ------------------------------------------------------------------
# 5. opencc
# ------------------------------------------------------------------
build_opencc() {
  echo "=== Building opencc for $PLATFORM ==="
  SRC="$DEPS_DIR/opencc"
  BUILD="$BUILD_DIR/opencc-$PLATFORM"
  cmake -S "$SRC" -B "$BUILD" "${CMAKE_ARGS[@]}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DUSE_SYSTEM_MARISA=OFF \
    -DSHARE_INSTALL_PREFIX=SharedSupport \
    -DBUILD_DOCUMENTATION=OFF \
    -DENABLE_GTEST=OFF \
    -DBUILD_OPENCC_TOOLS=OFF \
    -DBUILD_OPENCC_DATA=OFF
  cmake --build "$BUILD" --target install -j$(sysctl -n hw.ncpu)
}

# ------------------------------------------------------------------
# 6. yaml-cpp
# ------------------------------------------------------------------
build_yaml_cpp() {
  echo "=== Building yaml-cpp for $PLATFORM ==="
  SRC="$DEPS_DIR/yaml-cpp"
  BUILD="$BUILD_DIR/yaml-cpp-$PLATFORM"
  cmake -S "$SRC" -B "$BUILD" "${CMAKE_ARGS[@]}" \
    -DYAML_CPP_BUILD_TESTS=OFF \
    -DYAML_CPP_BUILD_TOOLS=OFF \
    -DBUILD_SHARED_LIBS=OFF
  cmake --build "$BUILD" --target install -j$(sysctl -n hw.ncpu)
}

# ------------------------------------------------------------------
# 7. librime
# ------------------------------------------------------------------
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
  cmake --build "$BUILD" --target install -j$(sysctl -n hw.ncpu)
}

# ------------------------------------------------------------------
# 8. Package each library as a static xcframework
# ------------------------------------------------------------------
make_xcframework() {
  local name=$1
  local lib=$2
  local output="$FRAMEWORKS_DIR/$name.xcframework"

  rm -rf "$output"

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

  xcodebuild -create-xcframework "${args[@]}" -output "$output"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
for PLATFORM in $PLATFORMS; do
  set_platform "$PLATFORM"
  echo "=== Building for $PLATFORM ($SDK, arch $ARCH) ==="

  build_boost
  for dep in $DEPS; do
    case $dep in
      glog) build_glog ;;
      leveldb) build_leveldb ;;
      marisa-trie) build_marisa ;;
      opencc) build_opencc ;;
      yaml-cpp) build_yaml_cpp ;;
    esac
  done
  build_librime
done

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

echo "=== Done. Frameworks in $FRAMEWORKS_DIR ==="
