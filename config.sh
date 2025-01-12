export GKI_VERSION="android12-5.10"

export TZ="Asia/Makassar"
export KBUILD_BUILD_USER="eraselk"
export KBUILD_BUILD_HOST="gacorprjkt"
export KBUILD_BUILD_TIMESTAMP=$(date)

export ANYKERNEL_REPO="https://github.com/Asteroidd21/Anykernel3"
export ANYKERNEL_BRANCH="gki"

export KERNEL_REPO="https://github.com/Asteroidd21/gki_android12-5.10"
export KERNEL_BRANCH="master"
export DEFCONFIG="gki_defconfig"
export KERNEL_IMAGE="$WORKDIR/out/arch/arm64/boot/Image"

export GKI_RELEASES_REPO="https://Asteroidd21:${gh_token}@github.com/Asteroidd21/gki-releases"

export USE_AOSP_CLANG="false"
export AOSP_CLANG_VERSION="r547379"

export USE_CUSTOM_CLANG="true"
export CUSTOM_CLANG_SOURCE="https://github.com/Asteroidd21/gacorprjkt-clang/releases/download/20250105-1441/clang.tar.zst"
# if it's a git repository then fill this
export CUSTOM_CLANG_BRANCH=""

# maybe you shouldn't edit this one
export MAKE_FLAGS="ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-"

export BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%y%m%d%H%M")
export ZIP_NAME="ambatubash69-KVER-OPTIONE-$BUILD_DATE.zip"
