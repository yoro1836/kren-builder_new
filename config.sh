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

export USE_AOSP_CLANG="false"
export AOSP_CLANG_VERSION="r547379"

export USE_CUSTOM_CLANG="true"
export CUSTOM_CLANG_SOURCE="https://github.com/Asteroidd21/gacorprjkt-clang/releases/download/20250105-1441/clang.tar.zst"
# if it's a git repository then fill this
export CUSTOM_CLANG_BRANCH=""
# if you have clang source which is not from github then fill this
export CUSTOM_CLANG_COMMAND=""

# maybe you shouldn't edit this one
export MAKE_FLAGS="ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-"

sleep 1
export RANDOM_HASH=$(head -c 20 /dev/urandom | sha1sum | head -c 7)
export ZIP_NAME="ambatubash69-KVER-OPTIONE-$RANDOM_HASH.zip"
