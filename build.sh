#!/usr/bin/env bash
set -e

ret=0
if [[ -z $chat_id ]]; then
    echo "error: please fill CHAT_ID secret!"
    let ret++
fi

if [[ -z $token ]]; then
    echo "error: please fill TOKEN secret!"
    let ret++
fi

if [[ -z $gh_token ]]; then
    echo "error: please fill GH_TOKEN secret!"
    let ret++
fi

[[ $ret -gt 0 ]] && exit $ret

mkdir -p android-kernel && cd android-kernel

WORKDIR=$(pwd)
source $WORKDIR/../config.sh

# ------------------
# Telegram functions
# ------------------

upload_file() {
    local file="$1"

    if [[ -f $file ]]; then
        chmod 777 "$file"
    else
        echo "[ERROR] file $file doesn't exist"
        exit 1
    fi

    curl -s -F document=@"$file" "https://api.telegram.org/bot$token/sendDocument" \
        -F chat_id="$chat_id" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=markdown" \
        -o /dev/null
}

send_msg() {
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot$token/sendMessage" \
        -d chat_id="$chat_id" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=markdown" \
        -d text="$msg" \
        -o /dev/null
}

# ---------------
# 	MAIN
# ---------------

# Add kernel variant into ZIP_NAME
if [[ $USE_KSU == "yes" ]]; then
    # ksu
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU/g')
elif [[ $USE_KSU_NEXT == "yes" ]]; then
    # ksu next
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU_NEXT/g')
else
    # vanilla
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
fi

# Clone the kernel source
git clone --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH $WORKDIR/common

# Extract kernel version
cd $WORKDIR/common
KERNEL_VERSION=$(make kernelversion)
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")
cd $WORKDIR

# Download Toolchains
mkdir $WORKDIR/clang
if [[ $USE_AOSP_CLANG == "true" ]]; then
    wget -qO $WORKDIR/clang.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-$AOSP_CLANG_VERSION.tar.gz
    tar -xf $WORKDIR/clang.tar.gz -C $WORKDIR/clang/
    rm -f $WORKDIR/clang.tar.gz
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
        echo "error: Clang source other than git is not supported."
        exit 1
    fi
elif [[ $USE_AOSP_CLANG == "true" ]] && [[ $USE_CUSTOM_CLANG == "true" ]]; then
    echo "error: You have to choose one, AOSP Clang or Custom Clang!"
    exit 1
else
    echo "stfu."
    exit 1
fi

# Clone binutils if they don't exist
if ! ls $WORKDIR/clang/bin | grep -q 'aarch64-linux-gnu'; then
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gas/linux-x86 -b main $WORKDIR/gas
    export PATH="$WORKDIR/clang/bin:$WORKDIR/gas:$PATH"
else
    export PATH="$WORKDIR/clang/bin:$PATH"
fi

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

# KSU or KSU-Next setup
if [[ $USE_KSU_NEXT == "yes" ]]; then
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
    echo "error: You have to choose one, KSU or KSUN!"
    exit 1
fi

git config --global user.email "kontol@example.com"
git config --global user.name "Your Name"

# SUSFS4KSU setup
if [[ $USE_KSU == "yes" ]] || [[ $USE_KSU_NEXT == "yes" ]] && [[ $USE_KSU_SUSFS == "yes" ]]; then
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu" -b "gki-$GKI_VERSION" $WORKDIR/susfs4ksu
    SUSFS_PATCHES="$WORKDIR/susfs4ksu/kernel_patches"

    cd $WORKDIR/common
    if [[ $USE_KSU == "yes" ]]; then
        ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU/KSUxSUSFS/g')
    elif [[ $USE_KSU_NEXT == "yes" ]]; then
        ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU_NEXT/KSUNxSUSFS/g')
    fi

    # Copy header files
    cp $SUSFS_PATCHES/include/linux/* ./include/linux/
    cp $SUSFS_PATCHES/fs/* ./fs/

    # Apply patch to KernelSU
    if [[ $USE_KSU == "yes" ]]; then
        cd $WORKDIR/KernelSU
        cp $SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch .
        patch -p1 <10_enable_susfs_for_ksu.patch || exit 1
    fi

    # Apply patch to kernel
    cd $WORKDIR/common
    cp $SUSFS_PATCHES/50_add_susfs_in_gki-$GKI_VERSION.patch .
    patch -p1 <50_add_susfs_in_gki-$GKI_VERSION.patch || exit 1

    # Special for KernelSU-Next
    if [[ $USE_KSU_NEXT == "yes" ]]; then
        cd $WORKDIR/KernelSU-Next
        patch -p1 <$WORKDIR/../patches/0001-Kernel-Implement-SUSFS-v1.5.3.patch || exit 1
    fi

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

elif [[ $USE_KSU_SUSFS == "yes" ]] && [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT != "yes" ]]; then
    echo "error: You can't use SuSFS without KSU enabled!"
    exit 1
fi

cd $WORKDIR

text=$(
    cat <<EOF
*~~~ QuartiX CI ~~~*
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
    make ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- $DEFCONFIG
    make ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- -j$(nproc --all)
) 2>&1 | tee $WORKDIR/build.log
set -e
cd $WORKDIR

if ! [[ -f $KERNEL_IMAGE ]]; then
    send_msg "❌ Build failed!"
    upload_file "$WORKDIR/build.log"
    exit 1
else
    # Clone AnyKernel
    git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" $WORKDIR/anykernel

    # Zipping
    cd $WORKDIR/anykernel
    sed -i "s/DUMMY1/$KERNEL_VERSION/g" anykernel.sh
    sed -i "s/DATE/$BUILD_DATE/g" anykernel.sh

    if [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT != "yes" ]]; then
        # vanilla
        sed -i "s/KSUDUMMY2 //g" anykernel.sh
    elif [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT == "yes" ]]; then
        # ksu next
        sed -i "s/KSU/KSU Next/g" anykernel.sh
    fi

    if [[ $USE_KSU_SUSFS == "yes" ]]; then
        # included ksu susfs
        sed -i "s/DUMMY2/ x SuSFS/g" anykernel.sh
    else
        # not included ksu susfs
        sed -i "s/DUMMY2//g" anykernel.sh
    fi

    cp $KERNEL_IMAGE .
    zip -r9 $ZIP_NAME * -x LICENSE
    mv $ZIP_NAME $WORKDIR
    cd $WORKDIR

    ## Release into GitHub
    TAG="$BUILD_DATE"
    RELEASE_MESSAGE="${ZIP_NAME%.zip}"
    DOWNLOAD_URL="$GKI_RELEASES_REPO/releases/download/$TAG/$ZIP_NAME"

    GITHUB_USERNAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $1}')
    REPO_NAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $2}')

    # Create a release tag
    $WORKDIR/../bin/github-release release \
        --security-token "$gh_token" \
        --user "$GITHUB_USERNAME" \
        --repo "$REPO_NAME" \
        --tag "$TAG" \
        --name "$RELEASE_MESSAGE"

    sleep 5

    # Upload the kernel zip
    $WORKDIR/../bin/github-release upload \
        --security-token "$gh_token" \
        --user "$GITHUB_USERNAME" \
        --repo "$REPO_NAME" \
        --tag "$TAG" \
        --name "$ZIP_NAME" \
        --file "$WORKDIR/$ZIP_NAME" || failed=yes

    if [[ $failed == "yes" ]]; then
        send_msg "❌ Failed to release into GitHub"
        exit 1
    else
        send_msg "📦 [Download]($DOWNLOAD_URL)"
    fi
    exit 0
fi
