#!/usr/bin/env bash
set -x

required_vars=("CHAT_ID" "TOKEN" "GH_TOKEN")

for var in "${required_vars[@]}"; do
    if [[ -z ${!var:-} ]]; then
        error "$var is not set!"
    fi
done

# Make sure we are on home directory
[[ $HOME == $(pwd) ]] || HOME=$(pwd)

# Setup git configurations
git config --global user.email "kontol@example.com"
git config --global user.name "Your Name"

# Import configuration
source $HOME/config.sh

# Set up timezone
sudo timedatectl set-timezone $TZ || {
    # Fallback since I did not know if timedatectl work in github action
    sudo rm -f /etc/localtime
    sudo ln -s /usr/share/zoneinfo/$TZ /etc/localtime
}

# ------------------
# Functions
# ------------------

# Telegram functions
upload_file() {
    local file="$1"

    if ! [[ -f $file ]]; then
        error "file $file doesn't exist"
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

# KernelSU installation function
install_ksu() {
    local repo="$1"
    local ref="$2" # Can be a branch or a tag

    [[ -z $repo ]] && {
        echo "Usage: install_ksu <repo-username/ksu-repo-name> [branch-or-tag]"
        return 1
    }

    # Fetch the latest tag (always needed for KSU_VERSION)
    local latest_tag=$(gh api repos/$repo/tags --jq '.[0].name')

    # Determine whether the reference is a branch or tag
    local ref_type="tags" # Default to tag
    if [[ -n $ref ]]; then
        # Check if the provided ref is a branch
        if gh api repos/$repo/branches --jq '.[].name' | grep -q "^$ref$"; then
            ref_type="heads"
        fi
    else
        ref="$latest_tag" # Default to latest tag
    fi

    # Construct the correct raw GitHub URL
    local url="https://raw.githubusercontent.com/$repo/refs/$ref_type/$ref/kernel/setup.sh"

    log "Installing KernelSU from $repo ($ref)..."
    curl -LSs "$url" | bash -s "$ref"

    # Always set KSU_VERSION to the latest tag
    KSU_VERSION="$latest_tag"
}

# Kernel scripts function
config() {
    $HOME/common/scripts/config "$@"
}

# Logging function
log() {
    echo -e "[\e[32mLOG\e[0m] $1" | tee -a $HOME/log.txt
}
error() {
    echo -e "\e[31m[ERROR]\e[0m $1" | tee -a $HOME/log.txt
    upload_file $HOME/log.txt
    exit 1
}

# ---------------
# 	MAIN
# ---------------

# Clone needed repositories
cd

# Kernel patches source
git clone --depth=1 https://github.com/ChiseWaguri/kernel-patches chise_patches
git clone --depth=1 https://github.com/WildPlusKernel/kernel_patches wildplus_patches
# Kernel source
git clone --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH common

# Extract kernel version
cd/common
KERNEL_VERSION=$(make kernelversion)

# Initialize VARIANT to "none" by default
VARIANT="none"

# Define an array of possible variants
for ksuvar in "USE_KSU_OFC KSU" "USE_KSU_NEXT KSUN" "USE_KSU_RKSU RKSU"; do
    read -r flag name <<< "$ksuvar" # Split the pair into flag and name
    if [[ ${!flag} == "true" ]]; then
        VARIANT="$name"
        break # Exit early when a match is found
    fi
done

# Append SUSFS if enabled
[[ $USE_KSU_SUSFS == "true" && $VARIANT != "none" ]] && VARIANT+="xSUSFS"

# Set ZIP_NAME with replacements
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")

# Handle VARIANT replacement in ZIP_NAME
if [[ $VARIANT == "none" ]]; then
    ZIP_NAME=${ZIP_NAME//VARIANT-/} # Remove "VARIANT-" if no variant
else
    ZIP_NAME=${ZIP_NAME//VARIANT/$VARIANT} # Replace VARIANT placeholder
fi

# Download Toolchains
cd

# Determine Clang source
if [[ "$USE_AOSP_CLANG" == "true" ]]; then
    CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-${AOSP_CLANG_VERSION}.tar.gz"
elif [[ "$USE_CUSTOM_CLANG" == "true" ]]; then
    CLANG_URL="$CUSTOM_CLANG_SOURCE"
else
    error "❌ No Clang toolchain selected. Set USE_AOSP_CLANG or USE_CUSTOM_CLANG."
fi

# Set CLANG_INFO
CLANG_INFO="$CLANG_URL"
if [[ "$CLANG_URL" != *.tar.* && -n "$CUSTOM_CLANG_BRANCH" ]]; then
    CLANG_INFO+=" | $CUSTOM_CLANG_BRANCH"
fi

# Check if Clang is already installed
CLANG_PATH="$HOME/tc"

if [[ ! -x $CLANG_PATH/bin/clang || ! -f $CLANG_PATH/VERSION || "$(cat $CLANG_PATH/VERSION)" != "$CLANG_INFO" ]]; then
    log "🔽 Downloading Clang from $CLANG_INFO..."
    rm -rf "$CLANG_PATH" && mkdir -p "$CLANG_PATH"

    if [[ "$USE_AOSP_CLANG" == "true" || "$CLANG_URL" == *.tar.* ]]; then
        wget -qO clang-tarball "$CLANG_URL" && tar -xf clang-tarball -C "$CLANG_PATH/" && rm clang-tarball
    else
        git clone --depth=1 --branch "$CUSTOM_CLANG_BRANCH" "$CLANG_URL" "$CLANG_PATH"
    fi

    echo "$CLANG_INFO" > "$CLANG_PATH/VERSION"
else
    log "✅ Using cached Clang: $CLANG_INFO."
fi

# Set Clang as compiler
export CC="ccache clang"
export CXX="ccache clang++"
export HOSTCC="$CC"
export HOSTCXX="$CXX"

# Set $PATH
export PATH="$CLANG_PATH/bin:$PATH"

# Ensure binutils (aarch64-linux-gnu) is available
if ! find "$CLANG_PATH/bin" -name "aarch64-linux-gnu-*" | grep -q .; then
    if find "$CLANG_PATH/binutils" -name "aarch64-linux-gnu-*" | grep -q .; then
        log "✅ aarch64-linux-gnu found in $CLANG_PATH/binutils."
    else
        log "🔍 aarch64-linux-gnu not found. Cloning binutils..."
        git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gas/linux-x86 "$CLANG_PATH/binutils" || error "❌ Failed to clone binutils."
    fi
    export PATH="$CLANG_PATH/binutils:$PATH"
else
    log "✅ aarch64-linux-gnu found in $CLANG_PATH."
fi

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

# Apply LineageOS maphide patch (thanks to @backslashxx and @WildPlusKernel)
cd/common
if ! patch -p1 < $HOME/wildplus_patches/69_hide_stuff.patch; then
    log "Patch rejected. Reverting patch..."
    mv fs/proc/task_mmu.c.orig fs/proc/task_mmu.c || true
    mv fs/proc/base.c.orig fs/proc/base.c || true
fi

# Apply extra tmpfs config
config --file arch/arm64/configs/$KERNEL_DEFCONFIG --enable CONFIG_TMPFS_XATTR
config --file arch/arm64/configs/$KERNEL_DEFCONFIG --enable CONFIG_TMPFS_POSIX_ACL

# KernelSU setup
# Remove KernelSU in driver in kernel source if exist
cd/common
if [[ $USE_KSU == true ]]; then
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
fi

# Install KernelSU driver
cd
if [[ $USE_KSU == true ]]; then
    [[ $USE_KSU_OFC == true ]] && install_ksu tiann/KernelSU
    [[ $USE_KSU_RKSU == true ]] && install_ksu rsuntk/KernelSU $([[ $USE_KSU_SUSFS == true ]] && echo "susfs-v1.5.5" || echo "main")
    [[ $USE_KSU_NEXT == true ]] && install_ksu rifsxd/KernelSU-Next $([[ $USE_KSU_SUSFS == true ]] && echo "next-susfs" || echo "next")
    [[ $USE_KSU_XX == true ]] && install_ksu backslashxx/KernelSU $([[ $USE_KSU_SUSFS == true ]] && echo "12055-sus155" || echo "magic")
fi

# SUSFS for KSU setup
if [[ $USE_KSU_SUSFS == "true" ]] && [[ $USE_KSU != "true" ]]; then
    error "You can't use SuSFS without KSU enabled!"
elif [[ $USE_KSU == "true" ]] && [[ $USE_KSU_SUSFS == "true" ]]; then
    git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu -b gki-$GKI_VERSION $HOME/susfs4ksu
    SUSFS_PATCHES="$HOME/susfs4ksu/kernel_patches"

    # Copy header files (Kernel Side)
    cd common
    cp $SUSFS_PATCHES/include/linux/* ./include/linux/
    cp $SUSFS_PATCHES/fs/* ./fs/
    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

    # Apply kernel-side susfs patch
    if ! patch -p1 < "$SUSFS_PATCHES/50_add_susfs_in_gki-$GKI_VERSION.patch" 2>&1 | tee ./patch.log; then
        grep -q "*FAILED*fs/devpts/inode.c*" ./patch.log || error "❌ Patch failed (not due to fs/devpts/inode.c)."

        log "⚠️ Kernel susfs patch failed on fs/devpts/inode.c."
        [[ $KSU_USE_MANUAL_HOOK == "true" ]] && log "⏩ Using manual hook, skipping fix." && rm -f ./patch.log && exit 0

        if grep -q "CONFIG_KSU_MANUAL_HOOK" fs/devpts/inode.c; then
            log "🔧 Applying inode.c fix..."
            patch -p1 < "$HOME/chise_patches/inode.c_fix.patch" || error "❌ inode.c fix patch failed."
        elif grep -q "CONFIG_KSU" fs/devpts/inode.c; then
            error "⚠️ CONFIG_KSU guard detected. Unsupported."
        else
            error "❌ Manual hook code missing or unknown guard."
        fi
    fi

    rm -f ./patch.log

    # Apply patch to KernelSU (KSU Side)
    if [[ $USE_KSU_OFC == "true" ]]; then
        cd ../KernelSU
        patch -p1 < $SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch || error "KernelSU susfs patch failed."
    fi
fi

cd/common
# Apply config for KernelSU manual hook (Need supported source on both kernel and KernelSU)
if [[ $KSU_USE_MANUAL_HOOK == "true" ]]; then
    [[ $USE_KSU_OFC == "true" ]] && (
        error "Official KernelSU drop manual hook support"
    )
    if ! grep -qE "CONFIG_KSU|CONFIG_KSU_MANUAL_HOOK" fs/exec.c; then
        ## WIP. will be uncommented later... or never
        # patch -p1 $HOME/chise_patches/ksu_manualhook.patch
        error "Your kernel source does not support manual hook for KernelSU"
    fi
    config --file arch/arm64/configs/$KERNEL_DEFCONFIG --enable CONFIG_KSU_MANUAL_HOOK
    config --file arch/arm64/configs/$KERNEL_DEFCONFIG --disable CONFIG_KSU_SUSFS_SUS_SU
fi

# Remove unnecessary code from scripts/setlocalversion
if grep -q '[-]dirty' scripts/setlocalversion; then
    sed -i 's/-dirty//' scripts/setlocalversion
fi
if grep -q 'echo "+"' scripts/setlocalversion; then
    sed -i 's/echo "+"/# echo "+"/g' scripts/setlocalversion
fi
# sed -i '$s|echo "\$res"|echo "\$res-v3.6.1-Chise-$BUILD_DATE+"|' scripts/setlocalversion

text=$(
    cat << EOF
*$HOME$HOME$HOME $KERNEL_NAME CI $HOME$HOME$HOME*
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

# Define make args
MAKE_ARGS="
-j$(nproc --all)
ARCH=arm64
LLVM=1
LLVM_IAS=1
O=$HOME/out
CROSS_COMPILE=aarch64-linux-gnu-
CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
"
KERNEL_IMAGE=$HOME/out/arch/arm64/boot/Image

# Build GKI
cd "$HOME/common"

if [[ $BUILD_KERNEL == "true" ]]; then
    log "Building kernel..."
    set +e
    {
        # Run defconfig
        make $MAKE_ARGS $KERNEL_DEFCONFIG

        # Disable module builds if needed
        if [[ $BUILD_LKMS != "true" ]]; then
            sed -i 's/=m/=n/g' "$HOME/out/.config"
        fi

        # Merge additional config files if provided
        if [[ -n "$DEFCONFIGS" ]]; then
            for CONFIG in $DEFCONFIGS; do
                echo "Merging $CONFIG..."
                make $MAKE_ARGS scripts/kconfig/merge_config.sh $CONFIG
            done
        fi

        # Ensure configuration is valid
        make $MAKE_ARGS olddefconfig

        # Build Kernel Image(s)
        build_targets="Image"
        if [[ $STATUS == "STABLE" || $BUILD_BOOTIMG == "true" ]]; then
            build_targets+=" Image.lz4 Image.gz"
        fi
        make $MAKE_ARGS -j$(nproc --all) \
            $build_targets

    } 2>&1 | tee -a "$HOME/build.log"
    set -e

elif [[ $GENERATE_DEFCONFIG == "true" ]]; then
    log "Generating defconfig..."
    make $MAKE_ARGS $KERNEL_DEFCONFIG
    upload_file $HOME/out/.config
    exit 0
fi

cd ..
if [[ ! -f $KERNEL_IMAGE ]]; then
    send_msg "❌ Build failed!"
    # Upload log and config for debugging
    echo "# Begin build log" >> $HOME/log.txt
    cat $HOME/build.log >> $HOME/log.txt
    upload_file "out/.config"
    error "Kernel Image does not exist at $KERNEL_IMAGE"
fi

# Post-compiling stuff
cd
# Clone AnyKernel
git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" anykernel

# Set kernel string
sed -i "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${KERNEL_VERSION} (${BUILD_DATE}) ${VARIANT}/g" $HOME/anykernel/anykernel.sh
if [[ $VARIANT == "none" ]]; then
    OLD=$(grep 'kernel.string' $HOME/anykernel/anykernel.sh | cut -f2 -d '=')
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
    git clone $AOSP_MIRROR/kernel/prebuilts/build-tools -b $BRANCH --depth=1 build-tools
    git clone $AOSP_MIRROR/platform/system/tools/mkbootimg -b $BRANCH --depth=1 mkbootimg

    # Variables
    KERNEL_IMAGES=$(echo out/arch/arm64/boot/Image*)
    AVBTOOL=$HOME/build-tools/linux-x86/bin/avbtool
    MKBOOTIMG=$HOME/mkbootimg/mkbootimg.py
    UNPACK_BOOTIMG=$HOME/mkbootimg/unpack_bootimg.py
    BOOT_SIGN_KEY_PATH=$HOME/key/verifiedboot.pem
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
        mv "$output" $HOME
    done
    cd
fi

# Zipping
cd anykernel
cp $KERNEL_IMAGE .
zip -r9 $HOME/$ZIP_NAME ./*
cd ..

if [[ $BUILD_LKMS == "true" ]]; then
    mkdir lkm && cd lkm
    find "$HOME/out" -type f -name "*.ko" -exec cp {} . \; || true
    [[ -n "$(ls -A ./*.ko 2> /dev/null)" ]] && zip -r9 "$HOME/lkm-$KERNEL_VERSION-$BUILD_DATE.zip" ./*.ko || echo "No LKMs found."
    cd ..
fi

if [[ $STATUS == "STABLE" ]] || [[ $UPLOAD2GH == "true" ]]; then
    ## Upload into GitHub Release
    TAG="$BUILD_DATE"
    RELEASE_MESSAGE="${ZIP_NAME%.zip}"
    URL="$GKI_RELEASES_REPO/releases/$TAG"
    GITHUB_USERNAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $1}')
    REPO_NAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $2}')

    # Clone repository
    git clone --depth=1 "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git" "$HOME/rel" || {
        error "❌ Failed to clone repository"
    }

    # Create release
    cd "$HOME/rel"
    gh release create "$TAG" -t "$RELEASE_MESSAGE" || {
        error "❌ Failed to create release"
    }

    sleep 2

    # Upload files to release
    for release_file in $HOME/*.zip $HOME/*.img; do
        [[ -f "$release_file" ]] || continue
        gh release upload "$TAG" "$release_file" || {
            error "❌ Failed to upload $release_file"
        }
    done

    send_msg "📦 [$RELEASE_MESSAGE]($URL)"
else
    cd
    send_msg "✅ Build Succeeded"
fi

exit 0
