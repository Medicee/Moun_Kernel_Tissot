#!/bin/bash
# Tissot (Mi A1) 4.9 kernel build for GitHub Actions.
# Based on the developer's build.sh: Android GCC 4.9 prebuilts, optional
# "Hybrid" cherry-picks, template/ + Image.gz + treble/nontreble dtbs -> zip.
# Env overrides: KV (version string), APPLY_HYBRID (true/false), TC_DIR.

set -euo pipefail

KV="${KV:-dev}"
APPLY_HYBRID="${APPLY_HYBRID:-true}"
TC_DIR="${TC_DIR:-$HOME/Toolchain}"
ROOT="$(pwd)"
NAME="Moun_Kernel_V${KV}-Tissot-4.9-Custom-Hybrid"
PKG="$HOME/Moun_Kernel/$NAME"
OUT="out"

echo "Compile is beginning... (version: $KV, hybrid: $APPLY_HYBRID)"

# ---------------- Toolchain (same prebuilts as developer's build.sh) ----------------
[ -d "$TC_DIR/64/bin" ] || git clone --depth=1 \
  https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 "$TC_DIR/64"
[ -d "$TC_DIR/32/bin" ] || git clone --depth=1 \
  https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9 "$TC_DIR/32"

export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE="$TC_DIR/64/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="$TC_DIR/32/bin/arm-linux-androideabi-"

# ---------------- ccache (wraps the prebuilt gcc explicitly) ----------------
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache_mikernel}"
export CCACHE_COMPILERCHECK=content
export CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime
if command -v ccache >/dev/null 2>&1; then
  CC_CMD="ccache ${CROSS_COMPILE}gcc"
else
  CC_CMD="${CROSS_COMPILE}gcc"
fi
MAKE_ARGS=(O="$OUT" CC="$CC_CMD" HOSTCC=gcc)
echo "CCACHE_DIR: [$CCACHE_DIR]"
"${CROSS_COMPILE}gcc" --version | head -n1

# ---------------- Hybrid commits (developer's cherry-picks) ----------------
if [ "$APPLY_HYBRID" = "true" ]; then
  git config user.name  >/dev/null 2>&1 || git config user.name  "ci"
  git config user.email >/dev/null 2>&1 || git config user.email "ci@example.invalid"
  echo "Picking Hybrid Commits"
  for c in fd4cd91a5a0f816aa48479afdc29e02a51e99221 \
           6205db338c6a8b87ec3243d13d6646666fd8cae7; do
    if git merge-base --is-ancestor "$c" HEAD 2>/dev/null; then
      echo "  $c already in history, skipping"
    else
      git cherry-pick "$c" || { git cherry-pick --abort || true; echo "ERROR: cherry-pick $c failed (missing object or conflict)" >&2; exit 1; }
    fi
  done
fi

# ---------------- WireGuard source (net/Kconfig sources it) ----------------
if [ ! -f net/wireguard/Kconfig ]; then
  echo "net/wireguard missing, fetching wireguard-linux-compat..."
  rm -rf /tmp/wg
  git clone --depth=1 https://git.zx2c4.com/wireguard-linux-compat /tmp/wg \
    || git clone --depth=1 https://github.com/WireGuard/wireguard-linux-compat /tmp/wg
  cp -r /tmp/wg/src net/wireguard
fi

# ---------------- Build ----------------
make "${MAKE_ARGS[@]}" tissot_defconfig
make "${MAKE_ARGS[@]}" -j"$(nproc)"

# ---------------- Package (developer's template layout) ----------------
[ -d template ] || { echo "ERROR: template/ directory not found in repo" >&2; exit 1; }

BOOT="$OUT/arch/arm64/boot"
DTS="$BOOT/dts/qcom"
for f in "$BOOT/Image.gz" "$DTS/msm8953-qrd-sku3-tissot-nontreble.dtb" "$DTS/msm8953-qrd-sku3-tissot-treble.dtb"; do
  [ -f "$f" ] || { echo "ERROR: missing $f"; ls "$BOOT" "$DTS" 2>/dev/null | grep -i -E "tissot|Image" || true; exit 1; }
done

rm -rf "$PKG"; mkdir -p "$PKG/kernel"
cp -r template/. "$PKG"
cp "$BOOT/Image.gz"                                     "$PKG/kernel/Image.gz"
cp "$DTS/msm8953-qrd-sku3-tissot-nontreble.dtb"         "$PKG/dtb-nontreble"
cp "$DTS/msm8953-qrd-sku3-tissot-treble.dtb"            "$PKG/dtb-treble"

( cd "$PKG" && zip -r9 "$ROOT/$NAME.zip" . -x '*.git*' )
echo "Done. The flashable zip is: [$ROOT/$NAME.zip]"
