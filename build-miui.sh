#!/bin/bash
# Standalone MIUI kernel build script.
# Only needs: TARGET_DEVICE / DEFCONFIG overridable via env; everything else
# is self-contained so it no longer depends on state from earlier CI steps.

set -euo pipefail

echo "Compile is beginning..."

# ---------------- Toolchain & env setup ----------------
export PATH="/usr/lib/ccache:$PATH"

export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache_mikernel}"
export CC="aarch64-linux-gnu-gcc"
export CXX="aarch64-linux-gnu-g++"
export CCACHE_COMPILERCHECK=content
export CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime

DEFCONFIG="${DEFCONFIG:-arch/arm64/configs/tissot_defconfig}"

MAKE_ARGS="ARCH=arm64 \
  SUBARCH=arm64 \
  O=out \
  CC=aarch64-linux-gnu-gcc \
  HOSTCC=gcc \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabihf- \
  CROSS_COMPILE_COMPAT=arm-linux-gnueabihf-"

echo "CCACHE_DIR: [$CCACHE_DIR]"
echo "DEFCONFIG: [$DEFCONFIG]"

# ---------------- Sanity check: toolchain resolvable ----------------
if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  echo "ERROR: aarch64-linux-gnu-gcc not found on PATH. Install with: sudo apt-get install gcc-aarch64-linux-gnu" >&2
  exit 1
fi
if ! command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
  echo "ERROR: arm-linux-gnueabihf-gcc not found on PATH. Install with: sudo apt-get install gcc-arm-linux-gnueabihf" >&2
  exit 1
fi

# ---------------- Config generation ----------------
if [ ! -f "out/.config" ]; then
  echo "Generating defconfig [$DEFCONFIG]......."
  # Extract just the filename to avoid path duplication in kernel build system
  make $MAKE_ARGS "$(basename "$DEFCONFIG")"
  
  echo "Resolving config dependencies......."
  make $MAKE_ARGS olddefconfig
  
  echo "Disabling unsupported stack protection feature......."
  ./scripts/config -d CONFIG_CC_STACKPROTECTOR_STRONG
  make $MAKE_ARGS olddefconfig
else
  echo "Existing out/.config found, skipping defconfig generation."
fi

# ---------------- Build ----------------
make $MAKE_ARGS -j"$(nproc)"

rm -rf anykernel/kernels/
mkdir -p anykernel/kernels/miui/

echo ".............Exporting the required images............."

cp out/arch/arm64/boot/Image anykernel/kernels/miui/
cp out/arch/arm64/boot/dtb anykernel/kernels/miui/
cp out/arch/arm64/boot/dtbo.img anykernel/kernels/miui/

echo "Build for MIUI finished."

# ------------- End of Building for MIUI -------------
#  If you don't need MIUI you can comment out the above block [Building for MIUI]
cd anykernel
ZIP_FILENAME=O-Kernel_v1.zip
zip -r9 "$ZIP_FILENAME" ./* -x .git .gitignore 'out/*' './*.zip'
mv "$ZIP_FILENAME" ../
cd ..
echo "Done. The flashable zip is: [./$ZIP_FILENAME]"
