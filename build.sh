#!/usr/bin/env bash
set -e

# Check chat_id and token
if [[ -z $chat_id ]]; then
    echo "error: please fill your CHAT_ID secret!"
    exit 1
fi

if [[ -z $token ]]; then
    echo "error: please fill TOKEN secret!"
    exit 1
fi

mkdir -p android-kernel && cd android-kernel

## Variables
WORKDIR=$(pwd)
source $WORKDIR/../config.sh

# Import telegram functions
source $WORKDIR/../telegram_functions.sh

# if ksu = yes
if [[ $USE_KSU == "yes" ]]; then
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU/g')
elif [[ $USE_KSU_NEXT == "yes" ]]; then
    # if ksu-next = yes
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU_NEXT/g')
else
    # if ksu = no
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
fi

# Clone kernel source
git clone --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH $WORKDIR/common

## Extract kernel version
cd $WORKDIR/common
KERNEL_VERSION=$(make kernelversion)
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")
cd $WORKDIR

## Download Toolchains
mkdir $WORKDIR/clang
if [[ $USE_AOSP_CLANG == "true" ]]; then
    wget -qO $WORKDIR/clang.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-$AOSP_CLANG_VERSION.tar.gz
    tar -xf $WORKDIR/clang.tar.gz -C $WORKDIR/clang/
    rm -f $WORKDIR/clang.tar.gz
    NO_BINUTILS=1
elif [[ $USE_CUSTOM_CLANG == "true" ]]; then
    if [[ $CUSTOM_CLANG_SOURCE =~ git ]]; then
        if [[ $CUSTOM_CLANG_SOURCE == *'.tar.'* ]]; then
            wget -q $CUSTOM_CLANG_SOURCE
            tar -C $WORKDIR/clang/ -xf $WORKDIR/*.tar.*
            rm -f $WORKDIR/*.tar.*
        else
            rm -rf $WORKDIR/clang
            git clone $CUSTOM_CLANG_SOURCE -b $CUSTOM_CLANG_BRANCH $WORKDIR/clang --depth=1
        fi
    else
        echo "Clang source other than git is not supported."
        exit 1
    fi

    if ! find "$WORKDIR/clang/bin" -name 'aarch64-linux-gnu-*' >/dev/null 2>&1; then
        NO_BINUTILS=1
    fi

elif [[ $USE_AOSP_CLANG == "true" ]] && [[ $USE_CUSTOM_CLANG == "true" ]]; then
    echo "You have to choose one, AOSP Clang or Custom Clang!"
    exit 1
else
    echo "stfu."
    exit 1
fi

if [[ -n $NO_BINUTILS ]]; then
    git clone --depth=1 https://github.com/XSans0/arm-linux-androideabi-4.9 $WORKDIR/gcc32
    git clone --depth=1 https://github.com/XSans0/aarch64-linux-android-4.9 $WORKDIR/gcc64
    export PATH="$WORKDIR/clang/bin:$WORKDIR/gcc64/bin:$WORKDIR/gcc32/bin:$PATH"
    MAKE_FLAGS=$(echo "$MAKE_FLAGS" | sed "s/CROSS_COMPILE=.*/CROSS_COMPILE=aarch64-linux-android-/g; s/CROSS_COMPILE_COMPAT=.*/CROSS_COMPILE_COMPAT=arm-linux-androideabi-/g")
else
    export PATH="$WORKDIR/clang/bin:$PATH"
fi

COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

## KSU or KSU-Next setup
if [[ $USE_KSU_NEXT == "yes" ]]; then
    if [[ $USE_KSU_SUSFS == "yes" ]]; then
        echo "KSU-Next doesn't support SuSFS by now. Please disable it."
        exit 1
    fi
    curl -LSs https://raw.githubusercontent.com/rifsxd/KernelSU-Next/refs/heads/next/kernel/setup.sh | bash -
    cd $WORKDIR/KernelSU-Next
    KSU_NEXT_VERSION=$(git describe --abbrev=0 --tags)
    cd $WORKDIR
elif [[ $USE_KSU == "yes" ]]; then
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/refs/heads/main/kernel/setup.sh" | bash -
    cd $WORKDIR/KernelSU
    KSU_VERSION=$(git describe --abbrev=0 --tags)
    cd $WORKDIR
elif [[ $USE_KSU_NEXT == "yes" ]] && [[ $USE_KSU == "yes" ]]; then
    echo
    echo "Bruh"
    exit 1
fi

## Apply kernel patches
git config --global user.email "kontol@example.com"
git config --global user.name "Your Name"

## SUSFS4KSU
if [[ $USE_KSU == "yes" ]] && [[ $USE_KSU_SUSFS == "yes" ]]; then
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu" -b "gki-$GKI_VERSION" $WORKDIR/susfs4ksu
    SUSFS_PATCHES="$WORKDIR/susfs4ksu/kernel_patches"

    cd $WORKDIR/common
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU/KSUxSUSFS/g')

    # Copy header files
    cp $SUSFS_PATCHES/include/linux/* ./include/linux/
    cp $SUSFS_PATCHES/fs/* ./fs/

    # Apply patch to KernelSU
    cd $WORKDIR/KernelSU
    cp $SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch .
    patch -p1 <10_enable_susfs_for_ksu.patch || exit 1

    # Apply patch to kernel
    cd $WORKDIR/common
    cp $SUSFS_PATCHES/50_add_susfs_in_gki-$GKI_VERSION.patch .
    patch -p1 <50_add_susfs_in_gki-$GKI_VERSION.patch || exit 1

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

elif [[ $USE_KSU_SUSFS == "yes" ]] && [[ $USE_KSU != "yes" ]]; then
    echo "[ERROR] You can't use SUSFS without KSU enabled!"
    exit 1
fi

cd $WORKDIR

text=$(
    cat <<EOF
*~~~ GKI Build Started ~~~*
*GKI Version*: \`$GKI_VERSION\`
*Kernel Version*: \`$KERNEL_VERSION\`
*Build Status*: \`$STATUS\`
*Date*: \`$KBUILD_BUILD_TIMESTAMP\`
*KSU*: \`$([[ $USE_KSU == "yes" ]] && echo "true" || echo "false")\`$([[ $USE_KSU == "yes" ]] && echo "
*KSU Version*: \`$KSU_VERSION\`")
*KSU-Next*: \`$([[ $USE_KSU_NEXT == "yes" ]] && echo "true" || echo "false")\`$([[ $USE_KSU_NEXT == "yes" ]] && echo "
*KSU-Next Version*: \`$KSU_NEXT_VERSION\`")
*SUSFS*: \`$([[ $USE_KSU_SUSFS == "yes" ]] && echo "true" || echo "false")\`$([[ $USE_KSU_SUSFS == "yes" ]] && echo "
*SUSFS Version*: \`$SUSFS_VERSION\`")
*Compiler*: \`$COMPILER_STRING\`
EOF
)

send_msg "$text"

# Build GKI
cd $WORKDIR/common
set +e
(
    make $MAKE_FLAGS $DEFCONFIG
    make $MAKE_FLAGS -j$(nproc --all)
) 2>&1 | tee $WORKDIR/build.log
set -e
cd $WORKDIR

# Upload to telegram
if ! [[ -f $KERNEL_IMAGE ]]; then
    send_msg "❌ GKI Build failed!"
    upload_file "$WORKDIR/build.log"
    exit 1
else
    send_msg "✅ GKI Build succeeded"

    # Clone AnyKernel
    git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" $WORKDIR/anykernel

    ## Zipping
    cd $WORKDIR/anykernel
    sed -i "s/DUMMY1/$KERNEL_VERSION/g" anykernel.sh

    if [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT != "yes" ]]; then
        sed -i "s/KSUDUMMY2 //g" anykernel.sh
    elif [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT == "yes" ]]; then
        sed -i "s/KSU/KSU-Next/g" anykernel.sh
    fi

    if [[ $USE_KSU_SUSFS == "yes" ]]; then
        sed -i "s/DUMMY2/xSUSFS/g" anykernel.sh
    else
        sed -i "s/DUMMY2//g" anykernel.sh
    fi

    cp $KERNEL_IMAGE .
    zip -r9 $ZIP_NAME * -x LICENSE
    mv $ZIP_NAME $WORKDIR
    cd $WORKDIR
    upload_file "$WORKDIR/$ZIP_NAME"
    upload_file "$WORKDIR/build.log"
    exit 0
fi
