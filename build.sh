#!/usr/bin/env bash
set -ex

ret=0
if [[ -z $CHAT_ID ]]; then
    echo "error: please fill CHAT_ID secret!"
    ((ret++))
fi

if [[ -z $TOKEN ]]; then
    echo "error: please fill TOKEN secret!"
    ((ret++))
fi

if [[ -z $GH_TOKEN ]]; then
    echo "error: please fill GH_TOKEN secret!"
    ((ret++))
fi

[[ $ret -gt 0 ]] && exit $ret

# Setup timezone
sudo rm /etc/localtime
sudo ln -s /usr/share/zoneinfo/$TZ /etc/localtime

# Setup directory
mkdir -p android-kernel && cd android-kernel
workdir=$(pwd)

# Import configuration
source ../config.sh

# ------------------
# Telegram functions
# ------------------

upload_file() {
    local file="$1"

    if ! [[ -f $file ]]; then
        echo "error: file $file doesn't exist"
        exit 1
    fi

    chmod 777 $file

    curl -s -F document=@"$file" "https://api.telegram.org/bot$TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=markdown" \
        -o /dev/null
}

send_msg() {
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=markdown" \
        -d text="$msg" \
        -o /dev/null
}

install_ksu() {
    setup_ksu() {
        curl -LSs $1 | bash -s $2
    }

    if [[ $# -eq 0 ]]; then
        echo "Usage: installksu <repo-username/ksu-repo-name> <commit-or-tag>"
        echo "Usage: installksu <repo-username/ksu-repo-name> (no args): Sets up the latest tagged version."
        return 1
    elif [[ -z $2 ]]; then
        local ksu_branch=$(gh api repos/$1 --jq '.default_branch')
        local ksu_setup_url=https://raw.githubusercontent.com/$1/refs/heads/$ksu_branch/kernel/setup.sh
        setup_ksu $ksu_setup_url
    else
        local ksu_setup_url=https://raw.githubusercontent.com/$1/refs/heads/$2/kernel/setup.sh
        setup_ksu $ksu_setup_url $2
    fi
}

apply_config() {
    if ! grep -q "$1" "$2"; then # if $1 doesn't exist in $2
        echo "$1" >>"$2"
    fi
}

# ---------------
# 	MAIN
# ---------------

# Kernel variant
if [[ $USE_KSU_OFC == "true" ]]; then # official ksu
    if [[ $USE_KSU_SUSFS == "true" ]]; then
        VARIANT="KSUxSUSFS"
    else
        VARIANT="KSU"
    fi
elif [[ $USE_KSU_NEXT == "true" ]]; then # ksun
    if [[ $USE_KSU_SUSFS == "true" ]]; then
        VARIANT="KSUNxSUSFS"
    else
        VARIANT="KSUN"
    fi
elif [[ $USE_KSU_RKSU == "true" ]]; then # rksu
    if [[ $USE_KSU_SUSFS == "true" ]]; then
        VARIANT="RKSUxSUSFS"
    else
        VARIANT="RKSU"
    fi
else
    # vanilla
    VARIANT="none"
fi

# Clone the kernel source
git clone --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH common

# Clone kernel patches source
git clone --depth=1 https://github.com/ChiseWaguri/kernel-patches chise_patches
git clone --depth=1 https://github.com/WildPlusKernel/kernel_patches wildplus_patches

# Extract kernel version
cd common
KERNEL_VERSION=$(make kernelversion)

# Download Toolchains
cd ..
mkdir clang
if [[ $USE_AOSP_CLANG == "true" ]] && [[ $USE_CUSTOM_CLANG == "true" ]]; then
    echo "error: You have to choose one, AOSP Clang or Custom Clang!"
    exit 1
elif [[ $USE_AOSP_CLANG == "true" ]]; then
    wget -qO clang.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-$AOSP_CLANG_VERSION.tar.gz
    tar -xf clang.tar.gz -C clang/
    rm -f clang.tar.gz
elif [[ $USE_CUSTOM_CLANG == "true" ]]; then
    if [[ $CUSTOM_CLANG_SOURCE == ./*'.tar.'* ]]; then
        wget -q $CUSTOM_CLANG_SOURCE
        tar -C clang/ -xf ./*.tar.*
        rm -f ./*.tar.*
    elif [[ $CUSTOM_CLANG_SOURCE =~ git ]]; then
        rm -rf clang
        git clone $CUSTOM_CLANG_SOURCE -b $CUSTOM_CLANG_BRANCH clang --depth=1
    else
        echo "error: Clang source other than git/tar is not supported."
        exit 1
    fi
else
    echo "stfu."
    exit 1
fi

# Clone binutils if they don't exist
if ! echo clang/bin/* | grep -q 'aarch64-linux-gnu'; then
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gas/linux-x86 -b main $(pwd)/binutils
    export PATH="$(pwd)/clang/bin:$(pwd)/binutils:$PATH"
else
    export PATH="$(pwd)/clang/bin:$PATH"
fi

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

# Apply LineageOS maphide patch
cd common
if ! patch -p1 <../wildplus_patches/69_hide_stuff.patch; then
    echo "Patch rejected. Reverting patch..."
    mv fs/proc/task_mmu.c.orig fs/proc/task_mmu.c || true
    mv fs/proc/base.c.orig fs/proc/base.c || true
fi

# Apply extra tmpfs config
apply_config 'CONFIG_TMPFS_XATTR=y' arch/arm64/configs/$KERNEL_DEFCONFIG
apply_config 'CONFIG_TMPFS_POSIX_ACL=y' arch/arm64/configs/$KERNEL_DEFCONFIG

# Remove KernelSU in driver in kernel source if exist
if [ -d drivers/staging/kernelsu ]; then
    sed -i '/kernelsu/d' drivers/staging/Kconfig
    sed -i '/kernelsu/d' drivers/staging/Makefile
    rm -rf drivers/staging/kernelsu
fi

if [ -d drivers/kernelsu ]; then
    sed -i '/kernelsu/d' drivers/Kconfig
    sed -i '/kernelsu/d' drivers/Makefile
    rm -rf drivers/kernelsu
fi

if [ -d KernelSU ]; then
    rm -rf KernelSU
fi

# kernelsu setup
cd ..

if [[ $USE_KSU == true ]]; then
    [[ $USE_KSU_OFC == true ]] && install_ksu tiann/KernelSU
    [[ $USE_KSU_RKSU == true ]] && install_ksu rsuntk/KernelSU $([[ $USE_KSU_SUSFS == true ]] && echo "susfs-v1.5.5-new")
    [[ $USE_KSU_NEXT == true ]] && install_ksu rifsxd/KernelSU-Next $([[ $USE_KSU_SUSFS == true ]] && echo "next-susfs")
fi

apply_config 'CONFIG_KSU=y' common/arch/arm64/configs/$KERNEL_DEFCONFIG

if [[ $KSU_USE_MANUAL_HOOK == "true" ]]; then
    apply_config 'CONFIG_KSU_MANUAL_HOOK=y' common/arch/arm64/configs/$KERNEL_DEFCONFIG
fi

git config --global user.email "kontol@example.com"
git config --global user.name "Your Name"

# SUSFS for KSU setup
if [[ $USE_KSU_SUSFS == "true" ]] && [[ $USE_KSU != "true" ]]; then
    echo "error: You can't use SuSFS without KSU enabled!"
    exit 1
elif [[ $USE_KSU == "true" ]] && [[ $USE_KSU_SUSFS == "true" ]]; then
    git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu -b gki-$GKI_VERSION susfs4ksu
    SUSFS_PATCHES="../susfs4ksu/kernel_patches"

    # Copy header files (Kernel Side)
    cd common
    cp $SUSFS_PATCHES/include/linux/* ./include/linux/
    cp $SUSFS_PATCHES/fs/* ./fs/
    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

    # Apply patch to kernel (Kernel Side)
    patch -p1 <$SUSFS_PATCHES/50_add_susfs_in_gki-$GKI_VERSION.patch || patch -p1 <../chise_patches/inode.c_fix.patch || exit 1

    # Apply patch to KernelSU (KSU Side)
    if [[ $USE_KSU_OFC == "true" ]]; then
        cd ../KernelSU
        patch -p1 <$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch || exit 1
    fi
    cd ..
fi

cd common

if grep -q '-dirty' scripts/setlocalversion; then
    sed -i 's/-dirty//' scripts/setlocalversion
fi

if grep -q 'echo "+"' scripts/setlocalversion; then
    sed -i 's/echo "+"/# echo "+"/g' scripts/setlocalversion
fi
# sed -i '$s|echo "\$res"|echo "\$res-v3.6.1-Chise-$BUILD_DATE+"|' scripts/setlocalversion

text=$(
    cat <<EOF
*~~~ $KERNEL_NAME CI ~~~*
*GKI Version*: \`$GKI_VERSION\`
*Kernel Version*: \`$KERNEL_VERSION\`
*Build Status*: \`$STATUS\`
*Date*: \`$KBUILD_BUILD_TIMESTAMP\`
*KSU Variant*: \`$VARIANT\`$(echo "$VARIANT" | grep -qi 'KSU' && echo "
*KSU Version*: \`$KSU_VERSION\`")
*SUSFS*: \`$([[ $USE_KSU_SUSFS == "true" ]] && echo "$SUSFS_VERSION" || echo "none")\`
*Compiler*: \`$COMPILER_STRING\`
EOF
)

send_msg "$text"

MAKE_ARGS="
-j$(nproc --all)
ARCH=arm64
LLVM=1
LLVM_IAS=1
O=$workdir/out
CROSS_COMPILE=aarch64-linux-gnu-
CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
"
KERNEL_IMAGE=$workdir/out/arch/arm64/boot/Image

# Build GKI
if [[ $BUILD_KERNEL == "true" ]]; then
    set +e
    (
        make $MAKE_ARGS $KERNEL_DEFCONFIG

        if [[ $BUILD_LKMS != "true" ]]; then
            sed -i 's/=m/=n/g' ../out/.config
        fi

        if [[ -n $DEFCONFIGS ]]; then
            for CONFIG in $DEFCONFIGS; do
                echo "Merging $CONFIG..."
                make $MAKE_ARGS scripts/kconfig/merge_config.sh $CONFIG
            done
        fi

        make $MAKE_ARGS olddefconfig

        make $MAKE_ARGS -j$(nproc --all) \
            Image $([[ $STATUS == "STABLE" ]] || [[ $BUILD_BOOTIMG == "true" ]] && echo "Image.lz4 Image.gz")

    ) 2>&1 | tee ../build.log
    set -e
elif [[ $GENERATE_DEFCONFIG == "true" ]]; then
    make $MAKE_ARGS $KERNEL_DEFCONFIG
    mv ../out/.config ../config
    send_msg "$(curl -s bashupload.com -T ../config)"
    exit 0
fi

cd ..

if ! [[ -f $KERNEL_IMAGE ]]; then
    send_msg "❌ Build failed!"
    upload_file build.log
    upload_file out/.config
    exit 1
fi

# Clone AnyKernel
git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" anykernel

ZIP_NAME=$(
    echo "$ZIP_NAME" |
        sed "s/KVER/$KERNEL_VERSION/g" |
        if [[ $VARIANT == "none" ]]; then
            sed "s/VARIANT-//g"
        else
            sed "s/VARIANT/$VARIANT/g"
        fi
)

sed -i "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${KERNEL_VERSION} (${BUILD_DATE}) ${VARIANT}/g" anykernel/anykernel.sh
if [[ $VARIANT == "none" ]]; then
    OLD=$(grep 'kernel.string' anykernel/anykernel.sh | cut -f2 -d '=')
    NEW=$(
        echo "$OLD" |
            sed "s/none//g"
    )
    sed -i "s/kernel.string=.*/kernel.string=${NEW}/g" anykernel/anykernel.sh
fi

if [[ $STATUS == "STABLE" ]] || [[ $BUILD_BOOTIMG == "true" ]]; then
    # Clone tools
    AOSP_MIRROR=https://android.googlesource.com
    BRANCH=main-kernel-build-2024
    git clone $AOSP_MIRROR/kernel/prebuilts/build-tools -b $BRANCH --depth=1
    git clone $AOSP_MIRROR/platform/system/tools/mkbootimg -b $BRANCH --depth=1

    # Variables
    KERNEL_IMAGES=$(echo out/arch/arm64/boot/Image*)
    AVBTOOL=$(pwd)/build-tools/linux-x86/bin/avbtool
    MKBOOTIMG=$(pwd)/mkbootimg/mkbootimg.py
    UNPACK_BOOTIMG=$(pwd)/mkbootimg/unpack_bootimg.py
    BOOT_SIGN_KEY_PATH=$(pwd)/../key/verifiedboot.pem
    BOOTIMG_NAME="${ZIP_NAME%.zip}-boot-dummy.img"
    # Note: dummy is the Image format

    # Function
    generate_bootimg() {
        local kernel="$1"
        local output="$2"

        # Create boot image
        $MKBOOTIMG --header_version 4 \
            --kernel "$kernel" \
            --output "$output" \
            --ramdisk out/ramdisk \
            --os_version 12.0.0 \
            --os_patch_level $(date +"%Y-%m")

        sleep 1

        # Sign the boot image
        $AVBTOOL add_hash_footer \
            --partition_name boot \
            --partition_size $((64 * 1024 * 1024)) \
            --image "$output" \
            --algorithm SHA256_RSA2048 \
            --key $BOOT_SIGN_KEY_PATH
    }

    # Prepare boot image
    mkdir -p bootimg && cd bootimg
    cp $KERNEL_IMAGES .

    # Download and unpack GKI
    wget -qO gki.zip https://dl.google.com/android/gki/gki-certified-boot-android12-5.10-2023-01_r1.zip
    unzip -q gki.zip && rm gki.zip
    $UNPACK_BOOTIMG --boot_img=./boot-5.10.img
    rm ./boot-5.10.img

    # Generate and sign boot images
    for format in raw lz4 gz; do

        case $format in
        raw)
            kernel="./Image"
            output="${BOOTIMG_NAME/dummy/raw}"
            ;;
        lz4)
            kernel="./Image.lz4"
            output="${BOOTIMG_NAME/dummy/lz4}"
            ;;
        gz)
            kernel="./Image.gz"
            output="${BOOTIMG_NAME/dummy/gz}"
            ;;
        esac

        # Generate and sign
        generate_bootimg "$kernel" "$output"
        mv "$output" ..
    done
    cd ..
fi

# Zipping
cp $KERNEL_IMAGE anykernel
zip -r9 $ZIP_NAME ./anykernel/*

if [[ $STATUS == "STABLE" ]] || [[ $UPLOAD2GH == "true" ]]; then
    ## Upload into GitHub Release
    TAG="$BUILD_DATE"
    RELEASE_MESSAGE="${ZIP_NAME%.zip}"
    URL="$GKI_RELEASES_REPO/releases/$TAG"
    GITHUB_USERNAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $1}')
    REPO_NAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $2}')

    # Clone repository
    if ! git clone --depth=1 "https://${GITHUB_USERNAME}:${GH_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git" rel; then
        echo "❌ Failed to clone GKI releases repository"
        exit 1
    fi

    cd rel

    # Create release
    if ! gh release create "$TAG" -t "$RELEASE_MESSAGE"; then
        echo "❌ Failed to create release $TAG"
        exit 1
    fi

    sleep 2

    # Upload files to release
    for release_file in ../*.zip ../*.img; do
        if [[ -f $release_file ]]; then
            if ! gh release upload "$TAG" "$release_file"; then
                echo "❌ Failed to upload $release_file"
                exit 1
            fi
            sleep 2
        fi
    done

    cd ..
fi

if [[ $STATUS == "STABLE" ]] || [[ $UPLOAD2GH == "true" ]]; then
    send_msg "📦 [$RELEASE_MESSAGE]($URL)"
else
    mv ./$ZIP_NAME ./*.img .. || true
    send_msg "✅ Build Succedded"
fi

exit 0
