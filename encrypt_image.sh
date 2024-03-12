#!/usr/bin/env bash

FILE_NAME="mk_encr_sd_rfs.sh"
INTERNAL_MEMORY="mmcblk0p"
CHECK_ENCRYPTION=$(lsblk -o type | grep crypt | wc -l)
EXTERNAL_DEVICE="/dev/sda"


format_usb_stick() {
    # Unmount the USB device if it is mounted
    umount $EXTERNAL_DEVICE*
    # Wipe partition table
    dd if=/dev/zero of=$EXTERNAL_DEVICE bs=512 count=1 >/dev/null
    # Format the USB stick in exFat file system
    echo -e "n\np\n\n\n\nw\n" | fdisk -W always $EXTERNAL_DEVICE >/dev/null
    mkfs.ext4 -j ${EXTERNAL_DEVICE}1 -F >/dev/null

    [ $? -ne 0 ] && echo "USB formate fail" || echo "USB formate success"
}

while ! fdisk -l "$EXTERNAL_DEVICE" >/dev/null 2>&1; do
    echo "No external device found. Please insert at least 64GB usb stick"
    read -p "Press Enter after inserting USB stick"
done

while [ "$(($(sudo fdisk -l "/dev/${INTERNAL_MEMORY}2" | awk 'NR==1 {print $5}') * 2))" \
    -ge "$(sudo fdisk -l "$EXTERNAL_DEVICE" | awk 'NR==1 {print $5}')" ]; do
    echo "USB stick memory size too small."
    read -p "Press Enter after inserting USB stick"
done

format_usb_stick

sudo ./$FILE_NAME -x $EXTERNAL_DEVICE >/dev/null 2>&1 &

echo "encryption started. It will take around 2 hours"
