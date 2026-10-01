#!/usr/bin/env bash
set -e

# Generate bundled data with a host librime build, keeping deployment out of the extension.
# Uses ../librime; run ./scripts/build-prebuilt-data.sh after schema changes.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIME_ROOT="${RIME_ROOT:-$ROOT/../librime}"
DEPS_DIR="$RIME_ROOT/deps"
BUILD_DIR="$ROOT/.build-host"
INSTALL_DIR="$BUILD_DIR/install"
SHARED_SUPPORT="$ROOT/Resources/SharedSupport"

export BOOST_ROOT="$DEPS_DIR/boost-1.89.0"

mkdir -p "$INSTALL_DIR"

HOST_CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"
)

# ------------------------------------------------------------------
# 1. Boost (host)
# ------------------------------------------------------------------
build_boost() {
  echo "=== Building host Boost ==="
  cd "$BOOST_ROOT"
  if [[ ! -f b2 ]]; then
    ./bootstrap.sh --with-toolset=clang --with-libraries=filesystem,regex,atomic
  fi
  ./b2 -a -q \
    --with-filesystem --with-regex --with-atomic \
    toolset=clang \
    link=static \
    variant=release \
    threading=multi \
    --stagedir="stage-host" \
    stage
  mkdir -p "$INSTALL_DIR/lib"
  cp "stage-host/lib/libboost_"*.a "$INSTALL_DIR/lib/"
  cp -R "$BOOST_ROOT/boost" "$INSTALL_DIR/include/" 2>/dev/null || true
}

# ------------------------------------------------------------------
# 2. deps (host)
# ------------------------------------------------------------------
build_dep() {
  local name=$1
  local src="$DEPS_DIR/$name"
  local bdir="$BUILD_DIR/$name-host"
  local extra=${2:-}
  echo "=== Building host $name ==="
  # shellcheck disable=SC2086
  cmake -S "$src" -B "$bdir" "${HOST_CMAKE_ARGS[@]}" $extra
  cmake --build "$bdir" --target install -j"$(sysctl -n hw.ncpu)"
}

# ------------------------------------------------------------------
# 3. librime (host, shared libs so rime_deployer is built)
# ------------------------------------------------------------------
build_librime() {
  echo "=== Building host librime (with rime_deployer) ==="
  local bdir="$BUILD_DIR/librime-host"
  cmake -S "$RIME_ROOT" -B "$bdir" "${HOST_CMAKE_ARGS[@]}" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_STATIC=ON \
    -DBUILD_MERGED_PLUGINS=ON \
    -DBUILD_TEST=OFF \
    -DBOOST_ROOT="$BOOST_ROOT" \
    -DBoost_NO_BOOST_CMAKE=TRUE \
    -DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
    -DCMAKE_FIND_ROOT_PATH="$INSTALL_DIR"
  cmake --build "$bdir" --target rime_deployer -j"$(sysctl -n hw.ncpu)"
}

# ------------------------------------------------------------------
# 4. Deploy SharedSupport -> build/*.bin
# ------------------------------------------------------------------
deploy() {
  echo "=== Deploying prebuilt data ==="
  local user_dir="$BUILD_DIR/deploy-user"
  local dep_path="$BUILD_DIR/librime-host/bin/rime_deployer"
  rm -rf "$user_dir"
  mkdir -p "$user_dir"
  rm -rf "$SHARED_SUPPORT/build"
  "$dep_path" --build "$user_dir" "$SHARED_SUPPORT"
  cp -R "$user_dir/build" "$SHARED_SUPPORT/build"
  echo "=== Prebuilt data written to $SHARED_SUPPORT/build ==="
  ls -la "$SHARED_SUPPORT/build"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
build_boost
build_dep glog        "-DWITH_GFLAGS=OFF -DBUILD_TESTING=OFF -DWITH_GTEST=OFF"
build_dep leveldb     "-DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF -DBUILD_SHARED_LIBS=OFF -DHAVE_CRC32C=OFF -DHAVE_SNAPPY=OFF -DHAVE_TCMALLOC=OFF"
build_dep marisa-trie "-DBUILD_SHARED_LIBS=OFF -DENABLE_TOOLS=OFF -DBUILD_TESTING=OFF"
build_dep opencc      "-DBUILD_SHARED_LIBS=OFF -DUSE_SYSTEM_MARISA=OFF -DBUILD_DOCUMENTATION=OFF -DENABLE_GTEST=OFF -DBUILD_OPENCC_TOOLS=OFF -DBUILD_OPENCC_DATA=OFF"
build_dep yaml-cpp    "-DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DBUILD_SHARED_LIBS=OFF"
build_librime
deploy

echo "=== Done ==="
