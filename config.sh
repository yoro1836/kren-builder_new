GKI_VERSION="android12-5.10"

TZ="Asia/Makassar"
KBUILD_BUILD_USER="eraselk"
KBUILD_BUILD_HOST="gacorprjkt"
KBUILD_BUILD_TIMESTAMP=$(date)

ANYKERNEL_REPO="https://github.com/Asteroidd21/Anykernel3"
ANYKERNEL_BRANCH="gki"

KERNEL_REPO="https://github.com/Asteroidd21/gki_android12-5.10"
KERNEL_BRANCH="master"
DEFCONFIG="gki_defconfig"
KERNEL_IMAGE="$WORKDIR/out/arch/arm64/boot/Image"

USE_AOSP_CLANG="false"
AOSP_CLANG_VERSION="r547379"

USE_CUSTOM_CLANG="true"
CUSTOM_CLANG_SOURCE="https://github.com/Asteroidd21/gacorprjkt-clang/releases/download/20250103-1011-WITA/clang.tar.zst"
# if it's a git repository then fill this
CUSTOM_CLANG_BRANCH=""
# if you have clang source which is not from github then fill this
CUSTOM_CLANG_COMMAND=""

# maybe you shouldn't edit this one
MAKE_FLAGS="ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-"

RANDOM_HASH=$(head -c 20 /dev/urandom | sha1sum | head -c 7)
ZIP_NAME="ambatubash69-KVER-OPTIONE-$RANDOM_HASH.zip"
