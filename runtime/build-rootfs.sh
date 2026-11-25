#!/usr/bin/env bash
# Builds the optional PRoot Ubuntu 24.04 Linux container bundle for AGY Go.
#
# By default, AGY Go runs Google's official native Android Bionic `agy` binary directly
# on arm64-v8a phones without needing PRoot. Run this script only if you want a full
# Ubuntu 24.04 Linux userland (git/python3/apt/bash) inside the APK or need x86_64 emulator support.
#
# Usage:
#   bash runtime/build-rootfs.sh arm64-v8a
#   bash runtime/build-rootfs.sh x86_64
set -euo pipefail

ABI="${1:-arm64-v8a}"
HERE="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="$HERE/.cache"
WORK="$HERE/.work/$ABI"
OUT="$HERE/out/$ABI"

UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.5}"
UBUNTU_MIRROR="${UBUNTU_MIRROR:-https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release}"
TERMUX_REPO="${TERMUX_REPO:-https://packages.termux.dev/apt/termux-main}"

case "$ABI" in
  arm64-v8a)
    UBUNTU_ARCH="arm64"
    TERMUX_ARCH="aarch64"
    AGY_PLATFORM="linux_arm64"
    ;;
  x86_64)
    UBUNTU_ARCH="amd64"
    TERMUX_ARCH="x86_64"
    AGY_PLATFORM="linux_amd64"
    ;;
  *)
    echo "error: unsupported ABI '$ABI' (expected arm64-v8a or x86_64)" >&2
    exit 1
    ;;
esac

for tool in curl sha256sum tar xz ar python3; do
  command -v "$tool" >/dev/null || { echo "error: missing host tool '$tool'" >&2; exit 1; }
done

mkdir -p "$CACHE" "$WORK" "$OUT/assets/runtime" "$OUT/jniLibs/$ABI"

fetch() {
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then return 0; fi
  echo "[rootfs] downloading $url"
  curl -fL --retry 3 --connect-timeout 20 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

# 1. Fetch Ubuntu Base tarball + SHA256SUMS verification
BASE_NAME="ubuntu-base-${UBUNTU_VERSION}-base-${UBUNTU_ARCH}.tar.gz"
fetch "$UBUNTU_MIRROR/SHA256SUMS" "$CACHE/ubuntu-${UBUNTU_VERSION}-SHA256SUMS"
fetch "$UBUNTU_MIRROR/$BASE_NAME" "$CACHE/$BASE_NAME"

EXPECTED_SHA="$(grep " \*${BASE_NAME}$" "$CACHE/ubuntu-${UBUNTU_VERSION}-SHA256SUMS" | awk '{print $1}')"
ACTUAL_SHA="$(sha256sum "$CACHE/$BASE_NAME" | awk '{print $1}')"
if [[ -z "$EXPECTED_SHA" || "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
  echo "error: Ubuntu base SHA-256 verification failed ($ACTUAL_SHA != $EXPECTED_SHA)" >&2
  rm -f "$CACHE/$BASE_NAME"
  exit 1
fi
echo "[rootfs] verified $BASE_NAME ($ACTUAL_SHA)"

# 2. Fetch Termux proot + libtalloc + libandroid-shmem for jniLibs
PACKAGES_IDX="$CACHE/termux-Packages-${TERMUX_ARCH}"
fetch "$TERMUX_REPO/dists/stable/main/binary-${TERMUX_ARCH}/Packages" "$PACKAGES_IDX"

extract_termux_pkg() {
  local pkg="$1"
  local rel_path
  rel_path="$(python3 - "$PACKAGES_IDX" "$pkg" <<'PY'
import sys
idx_path, want = sys.argv[1], sys.argv[2]
cur = {}
with open(idx_path, "r", encoding="utf-8", errors="replace") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            if cur.get("Package") == want and "Filename" in cur:
                print(cur["Filename"])
                sys.exit(0)
            cur = {}
        elif ":" in line and not line[0].isspace():
            k, v = line.split(":", 1)
            cur[k.strip()] = v.strip()
    if cur.get("Package") == want and "Filename" in cur:
        print(cur["Filename"])
        sys.exit(0)
sys.exit(1)
PY
)"
  local deb="$CACHE/$(basename "$rel_path")"
  fetch "$TERMUX_REPO/$rel_path" "$deb"
  local stage="$WORK/pkg-$pkg"
  rm -rf "$stage" && mkdir -p "$stage"
  (cd "$stage" && ar x "$deb")
  local data_tar
  data_tar="$(find "$stage" -maxdepth 1 -name 'data.tar.*' | head -n 1)"
  tar -xf "$data_tar" -C "$stage"
}

extract_termux_pkg "proot"
extract_termux_pkg "libtalloc"
extract_termux_pkg "libandroid-shmem"

PROOT_BIN="$(find "$WORK/pkg-proot" -type f -name 'proot' | head -n 1)"
LOADER_BIN="$(find "$WORK/pkg-proot" -type f -name 'loader' | head -n 1)"
TALLOC_SO="$(find "$WORK/pkg-libtalloc" -type f -name 'libtalloc.so*' | head -n 1)"
SHMEM_SO="$(find "$WORK/pkg-libandroid-shmem" -type f -name 'libandroid-shmem.so*' | head -n 1)"

cp -f "$PROOT_BIN" "$OUT/jniLibs/$ABI/libproot.so"
[[ -n "${LOADER_BIN:-}" ]] && cp -f "$LOADER_BIN" "$OUT/jniLibs/$ABI/libproot-loader.so"
cp -f "$TALLOC_SO" "$OUT/jniLibs/$ABI/libtalloc.so"
cp -f "$SHMEM_SO" "$OUT/jniLibs/$ABI/libandroid-shmem.so"

# 3. Repack Ubuntu rootfs into deterministic tar.xz with DNS & /root/workspace defaults
ROOTFS_STAGE="$WORK/rootfs"
rm -rf "$ROOTFS_STAGE" && mkdir -p "$ROOTFS_STAGE"
tar -xzf "$CACHE/$BASE_NAME" -C "$ROOTFS_STAGE" --exclude='dev/*' 2>/dev/null || tar -xzf "$CACHE/$BASE_NAME" -C "$ROOTFS_STAGE"
mkdir -p "$ROOTFS_STAGE/root/workspace" "$ROOTFS_STAGE/etc"
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$ROOTFS_STAGE/etc/resolv.conf"

OUT_TAR="$OUT/assets/runtime/rootfs.tar.xz"
tar -C "$ROOTFS_STAGE" -c . | xz -T0 -6 > "$OUT_TAR"
OUT_SHA="$(sha256sum "$OUT_TAR" | awk '{print $1}')"

cat > "$OUT/assets/runtime/proot-manifest.json" <<JSON
{
  "abi": "$ABI",
  "ubuntuVersion": "$UBUNTU_VERSION",
  "agyPlatform": "$AGY_PLATFORM",
  "archive": "rootfs.tar.xz",
  "sha256": "$OUT_SHA"
}
JSON

echo "[rootfs] done: $OUT_TAR (sha256=$OUT_SHA)"
echo "[rootfs] jniLibs ready in $OUT/jniLibs/$ABI"
