#!/bin/bash
set -e

set_language() {
    MSG_SYSTEM_INFO="SYSTEM INFO:"
    MSG_ARCH="ARCH:"
    MSG_BOOTMODE="BOOT MODE:"
    MSG_STORAGE_DEVICE="STORAGE:"
    MSG_ETH_DEVICE="ETH:"
    MSG_ADDRESS="ADDRESS:"
    MSG_GATEWAY="GATEWAY:"
    MSG_DNS="DNS:"
    MSG_SELECT_VERSION="Select the version you want to install:"
    MSG_STABLE="stable (v7)"
    MSG_TEST="testing (v7)"
    MSG_LTS="long-term (v6)"
    MSG_STABLE6="stable (v6)"
    MSG_PLEASE_CHOOSE="Please choose an option:"
    MSG_UNSUPPORTED_ARCH="Error: Unsupported architecture: "
    MSG_INVALID_OPTION="Error: Invalid option!"
    MSG_ARM64_NOT_SUPPORT_V6="arm64 does not support v6 version for now."
    MSG_SELECTED_VERSION="Selected version:"
    MSG_FILE_DOWNLOAD="Download file: "
    MSG_DOWNLOAD_ERROR="Error: No wget nor curl is installed. Cannot download."
    MSG_EXTRACT_ERROR="Error: No unzip nor gunzip is installed. Cannot uncompress."
    MSG_DOWNLOAD_FAILED="Error: Download failed!"
    MSG_OPERATION_ABORTED="Error: Operation aborted."
    MSG_WARNING="Warn: All data on /dev/%s will be lost!"
    MSG_REBOOTING="Ok, rebooting..."
    MSG_ADMIN_PASSWORD="admin password:"
    MSG_MANUAL_PASS_CHOICE="Do you want to enter a password manually? (y/N): "
    MSG_ENTER_NEW_PASS="Enter new password: "
    MSG_PASS_EMPTY="Password cannot be empty, please try again."
    MSG_ERROR_MOUNT="Error: Failed to mount partition"
    MSG_ERROR_LOOP="Error: Failed to setup loop device"
    MSG_AUTO_RUN_FILE_CREATED="autorun.scr file created."
    MSG_CONFIRM_CONTINUE="Do you want to continue? [Y/n]:"
}

show_system_info() {
    ARCH=$(uname -m)
    BOOT_MODE=$( [ -d "/sys/firmware/efi" ] && echo "UEFI" || echo "BIOS" )
    STORAGE=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk"{print $1; exit}')
    ETH=$(ip route show default | grep '^default' | sed -n 's/.* dev \([^\ ]*\) .*/\1/p')
    ADDRESS=$(ip addr show $ETH | grep global | cut -d' ' -f 6 | head -n 1)
    GATEWAY=$(ip route list | grep default | cut -d' ' -f 3)
    DNS=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | head -n 1)
    [ -z "$DNS" ] && DNS="8.8.8.8"
    echo "$MSG_SYSTEM_INFO"
    echo "$MSG_ARCH $ARCH"
    echo "$MSG_BOOTMODE $BOOT_MODE"
    echo "$MSG_STORAGE_DEVICE $STORAGE"
    echo "$MSG_ETH_DEVICE $ETH"
    echo "$MSG_ADDRESS $ADDRESS"
    echo "$MSG_GATEWAY $GATEWAY"
    echo "$MSG_DNS $DNS"
}

select_version() {
    if [[ -n "$VERSION" ]]; then
        if [[ "$VERSION" == 7.* ]]; then
            V7=1
        elif [[ "$VERSION" == 6.* ]]; then
            V7=0
        else
            echo "Error: Unsupported version $VERSION"
            exit 1
        fi
        echo "$MSG_SELECTED_VERSION $VERSION"
        return
    fi
    while true; do
        case $ARCH in
            x86_64|i386|i486|i586|i686)
                echo "$MSG_SELECT_VERSION"
                echo "1. $MSG_STABLE"
                echo "2. $MSG_TEST"
                echo "3. $MSG_LTS"
                echo "4. $MSG_STABLE6"
                read -p "$MSG_PLEASE_CHOOSE [1-4]" version_choice
                ;; 
            aarch64)
                echo "$MSG_SELECT_VERSION"
                echo "1. $MSG_STABLE"
                echo "2. $MSG_TEST"
                read -p "$MSG_PLEASE_CHOOSE [1-2]" version_choice
                ;; 
            *)
                echo "$MSG_UNSUPPORTED_ARCH $ARCH"
                exit 1
                ;;
        esac
        case $version_choice in
            1) VERSION=$(curl -s "https://upgrade.mikrotik.ltd/routeros/NEWESTa7.stable" | cut -d' ' -f1); V7=1 ;;
            2) VERSION=$(curl -s "https://upgrade.mikrotik.ltd/routeros/NEWESTa7.testing" | cut -d' ' -f1); V7=1 ;;
            3)
                if [[ "$ARCH" == "aarch64" ]]; then
                    echo "$MSG_ARM64_NOT_SUPPORT_V6"
                    continue
                fi
                VERSION=$(curl -s "https://upgrade.mikrotik.ltd/routeros/NEWEST6.long-term" | cut -d' ' -f1)
                V7=0
                ;;
            4)
                if [[ "$ARCH" == "aarch64" ]]; then
                    echo "$MSG_ARM64_NOT_SUPPORT_V6"
                    continue
                fi
                VERSION=$(curl -s "https://upgrade.mikrotik.ltd/routeros/NEWEST6.stable" | cut -d' ' -f1)
                V7=0
                ;;
            *)
                echo "$MSG_INVALID_OPTION"
                continue
                ;;
        esac
        echo "$MSG_SELECTED_VERSION $VERSION"
        break
    done
}

download_image(){
    case $ARCH in
        x86_64|i386|i486|i586|i686)
            if [[ $V7 == 1 && $BOOT_MODE == "BIOS" ]]; then
                IMG_URL="https://github.com/elseif/MikroTikPatch/releases/download/$VERSION/chr-$VERSION-legacy-bios.img.zip"
            else
                IMG_URL="https://github.com/elseif/MikroTikPatch/releases/download/$VERSION/chr-$VERSION.img.zip"
            fi
            ;; 
        aarch64)
             IMG_URL="https://github.com/elseif/MikroTikPatch/releases/download/$VERSION-arm64/chr-$VERSION-arm64.img.zip"
            ;; 
        *)
            echo "$MSG_UNSUPPORTED_ARCH"
            exit 1
            ;;
    esac
    echo "$MSG_FILE_DOWNLOAD $(basename "$IMG_URL")"
    if command -v curl >/dev/null 2>&1; then
        curl -L -# -o /tmp/chr.img.zip "$IMG_URL" || { echo "$MSG_DOWNLOAD_FAILED"; exit 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -nv -O /tmp/chr.img.zip "$IMG_URL" || { echo "$MSG_DOWNLOAD_FAILED"; exit 1; }
    el
        echo "$MSG_DOWNLOAD_ERROR $IMG_URL"
        exit 1
    fi
    cd /tmp
    if command -v unzip >/dev/null 2>&1; then
        unzip -p "chr.img.zip" > chr.img
    elif command -v gunzip >/dev/null 2>&1; then
        gunzip -c chr.img.zip > chr.img
    else
        echo "$MSG_EXTRACT_ERROR"
        exit 1
    fi
}

create_autorun() {
    
    if LOOP=$(losetup -Pf --show chr.img 2>/dev/null); then
        sleep 1
        MNT=/tmp/chr
        mkdir -p $MNT
        PARTITION=$([ "$V7" == 1 ] && echo "p2" || echo "p1")
        if mount "${LOOP}${PARTITION}" "$MNT" 2>/dev/null; then
            RANDOM_ADMIN_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
            echo -e "$MSG_ADMIN_PASSWORD \e[31m$RANDOM_ADMIN_PASS\e[0m"
            read -p "$MSG_MANUAL_PASS_CHOICE" input_pass_choice < /dev/tty
            input_pass_choice=${input_pass_choice:-N}
            if [[ "$input_pass_choice" =~ ^[Yy]$ ]]; then
                while true; do
                    read -p "$MSG_ENTER_NEW_PASS" user_pass
                    if [[ -n "$user_pass" ]]; then
                        RANDOM_ADMIN_PASS="$user_pass"
                        echo -e "$MSG_ADMIN_PASSWORD \e[31m$RANDOM_ADMIN_PASS\e[0m"
                        break
                    else
                        echo "$MSG_PASS_EMPTY"
                    fi
                done
            fi
            cat <<EOF > "$MNT/rw/autorun.scr"
/ip dhcp-client disable [ /ip dhcp-client find ]
/ip address add address=$ADDRESS interface=ether1
/ip route add gateway=$GATEWAY
/ip dns set servers=$DNS
/user set admin password="$RANDOM_ADMIN_PASS"
EOF
            echo "$MSG_AUTO_RUN_FILE_CREATED"
            umount $MNT
            losetup -d "$LOOP"
        else
            losetup -d "$LOOP"
            echo "$MSG_ERROR_MOUNT $PARTITION"
            exit 1
        fi
    else
        echo "$MSG_ERROR_LOOP"
        exit 1
    fi
}


write_and_reboot() {
    printf "$MSG_WARNING\n" "$STORAGE"
    read -p "$MSG_CONFIRM_CONTINUE" confirm < /dev/tty
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "$MSG_OPERATION_ABORTED"
        exit 1
    fi
    dd if=chr.img of=/dev/$STORAGE bs=4M conv=fsync
    echo "$MSG_REBOOTING"
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
    echo b > /proc/sysrq-trigger 2>/dev/null || true
    reboot -f
}

set_language
show_system_info
select_version
download_image
create_autorun
write_and_reboot
exit 0
