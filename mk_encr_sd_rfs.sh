#!/bin/bash
#
# This script will make an encrypted root file system on the RPi SD card.
# This script needs an external storage device which is used for hosting
# a temporary root file system as well as storing the temporary backup
# of the root file system on the SD card. The script is equipped to
# recognize if the external drive already has the necessary components
# installed so that the migration can be expedited.

# Ensure running as root or exit
if [ "$(id -u)" != "0" ]
then
  echo "run this as root or use sudo" 2>&1 && exit 1
fi

# Check for NVIDIA platform
nv_model_fn="/proc/device-tree/model"
if [ -e  ${nv_model_fn} ]
then
   grep -i "Nano" ${nv_model_fn}
   if [ $? -eq 0 ]
   then
      echo "Running on NVIDIA platform. Getting NVIDIA Nano script..."
      curl -G https://s3.amazonaws.com/zk-sw-repo/mk_encr_sd_rfs_nvidia.sh | bash
      exit $?
   fi
fi

if [ -e  ${nv_model_fn} ]
then
   grep -i "Xavier" ${nv_model_fn}
   if [ $? -eq 0 ]
   then
      echo "Running on NVIDIA platform. Getting NVIDIA Xavier script..."
      curl -G https://s3.amazonaws.com/zk-sw-repo/mk_encr_sd_rfs_nvidia_xavier.sh | bash
      exit $?
   fi
fi

usage()
{
    echo "mk_encr_sd_rfs.sh" 1>&2
    echo "params:" 1>&2
    echo "      -x      path to external device used for temp storage." 1>&2
    echo "              Defaults to /dev/sda." 1>&2
    echo "      -m      SD card partition to encrypt." 1>&2
    echo "              Defaults to 2." 1>&2
    echo "example:" 1>&2
    echo "      ./mk_encr_sd_rfs.sh -x /dev/sda -m 7" 1>&2
    exit 1
}

source /var/lib/zymbit/zkenv.conf >/dev/null 2>&1
export ZK_GPIO_WAKE_PIN

RFS_SRC_PART_NUM="2"

while getopts ":x:m:h" o; do
    case "${o}" in
        x)
            EXT_DEV=${OPTARG}
            if [ ! -e "${EXT_DEV}" ]
            then
                echo "specified external device ${EXT_DEV} does not exist"; usage
                exit
            fi
            ;;
        m)
            RFS_SRC_PART_NUM=${OPTARG}
            if [ ${RFS_SRC_PART_NUM} = 1 ]
            then
                echo "ERROR: /boot partition specified. Aborting..."
                exit
            fi
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z ${EXT_DEV} ]
then
    echo "No temporary volume name (/dev/...) specified. Defaulting to /dev/sda..."
    EXT_DEV="/dev/sda"
fi

SRC_RFS_PART="/dev/mmcblk0p${RFS_SRC_PART_NUM}"
EXT_TMP_PART="${EXT_DEV}1"
crfsvol="/mnt/cryptrfs"
tmpvol="/mnt/tmproot"

mk_SD_crfs_script()
{
cat > /usr/local/bin/cfg_SD_crfs.sh <<"EOF"
#!/bin/bash

# Make a zymkey-locked LUKS key
echo -n "Creating LUKS key..."
ct=0
while [ $ct -lt 3 ]
do
  sleep 1
  let ct=ct+1
  zkgrifs 512 > /run/key.bin
  if [ $? -ne 0 ]
  then
    echo "Retrying zkgrifs..."
    continue
  fi
  zklockifs /run/key.bin > /var/lib/zymbit/key.bin.lock
  if [ $? -ne 0 ]
  then
    echo "Retrying zklockifs..."
  else
    break
  fi
done
if [ $ct -ge 3 ]
then
  echo "LUKS key creation failed"
  exit
fi
echo "done."
EOF

cat >> /usr/local/bin/cfg_SD_crfs.sh <<EOF

# Create the dm-crypt volume on ${SRC_RFS_PART}
echo -n "Formatting crypto file system on ${SRC_RFS_PART}..."
cat /run/key.bin | cryptsetup -q -v luksFormat ${SRC_RFS_PART} - >/dev/null
cat /run/key.bin | cryptsetup luksOpen ${SRC_RFS_PART} cryptrfs --key-file=- >/dev/null
echo "done."
echo -n "Creating ext4 partition on ${SRC_RFS_PART}..."
mkfs.ext4 -j /dev/mapper/cryptrfs -F >/dev/null || exit
echo "done."

echo "Copying files to crypto fs..."
mkdir -p ${crfsvol}
mount /dev/mapper/cryptrfs ${crfsvol} >/dev/null || exit
tar -xpf /original_zk_root.tgz -C ${crfsvol}
echo "done."

echo -n "Copying /var/lib/zymbit to crypto fs..."
rm -rf ${crfsvol}/var/lib/zymbit
cp -rpf /var/lib/zymbit ${crfsvol}/var/lib/
echo "done."

echo -n "Copying hostname..."
cp /etc/hosts ${crfsvol}/etc
cp /etc/hostname ${crfsvol}/etc
echo "done."

echo -n "Copying ssh keys..."
cp /etc/ssh/*_key* ${crfsvol}/etc/ssh

# Mount the boot partition in a safe place
mkdir -p /mnt/tmpboot
mount /dev/mmcblk0p1 /mnt/tmpboot || exit

# Remove the plaintext key now
rm /run/key.bin

# Change fstab to no longer use the unencrypted root volume
echo -n "Configuring fstab..."
pushd ${crfsvol}/etc/
cp /etc/fstab .
sed -i -e '/# temp root fs/,+1d' fstab
EOF
cat >> /usr/local/bin/cfg_SD_crfs.sh <<"EOF"
rootln=`grep -w "/" fstab | grep -ve "^#"`
if [ -n "${rootln}" ]
then
  sed -i "s|^${rootln}|#${rootln}|" fstab
fi
EOF
cat >> /usr/local/bin/cfg_SD_crfs.sh <<EOF
popd
grep -q "^/dev/mapper/cryptrfs" ${crfsvol}/etc/fstab || echo -e "\n# crypto root fs\n/dev/mapper/cryptrfs /             ext4    defaults,noatime  0       1" >> ${crfsvol}/etc/fstab
mv /etc/fstab /etc/fstab.prev
cp ${crfsvol}/etc/fstab /etc/fstab
echo "done."

# Make sure that boot uses initramfs
echo -n "Configuring config.txt..."
grep -q "^initramfs" /mnt/tmpboot/config.txt || echo "initramfs initrd.img followkernel" >> /mnt/tmpboot/config.txt
echo "done."

# Add crypto fs stuff to the kernel command line
echo -n "Configuring kernel cmd line..."
sed -i "s/root=[^ ]*//" /mnt/tmpboot/${cmdline}
sed -i "s/rootfstype=[^ ]*//" /mnt/tmpboot/${cmdline}
sed -i "s/cryptdevice=[^ ]*//" /mnt/tmpboot/${cmdline}
tr -d '\n' </mnt/tmpboot/${cmdline}> /tmp/${cmdline}
mv /tmp/${cmdline} /mnt/tmpboot/${cmdline}
echo " root=/dev/mapper/cryptrfs cryptdevice=${SRC_RFS_PART}:cryptrfs rng_core.default_quality=1000" >> /mnt/tmpboot/${cmdline}
echo "done."

# Add crypttab cfg
echo -n "Configuring crypttab..."
echo -e "cryptrfs\t${SRC_RFS_PART}\t/etc/cryptroot/key.bin\tluks,keyscript=/lib/cryptsetup/scripts/zk_get_key,tries=100,timeout=30s" > ${crfsvol}/etc/crypttab
cp ${crfsvol}/etc/crypttab /etc/crypttab
echo "done."

# Bring the i2c drivers into initramfs
echo -n "Adding i2c drivers to initramfs..."
grep -q "^i2c-dev" /etc/initramfs-tools/modules || echo "i2c-dev" >> /etc/initramfs-tools/modules
grep -q "^i2c-bcm2835" /etc/initramfs-tools/modules || echo "i2c-bcm2835" >> /etc/initramfs-tools/modules
grep -q "^i2c-bcm2708" /etc/initramfs-tools/modules || echo "i2c-bcm2708" >> /etc/initramfs-tools/modules
grep -q "^lan78xx" /etc/initramfs-tools/modules || echo "lan78xx" >> /etc/initramfs-tools/modules
cp -rpf /etc/initramfs-tools/modules ${crfsvol}/etc/initramfs-tools
echo "done."

# chroot to future root fs
mount -t proc /proc ${crfsvol}/proc/
mount --rbind /sys ${crfsvol}/sys/
mount --rbind /dev ${crfsvol}/dev/
mount --rbind /run ${crfsvol}/run/
mkdir -p ${crfsvol}/mnt/tmpboot/
mount --bind /mnt/tmpboot ${crfsvol}/mnt/tmpboot/
cat << EOF1 | chroot ${crfsvol} /bin/bash

# Make the initramfs
echo -n "Building initramfs..."
rm /mnt/tmpboot/initrd.img-`uname -r` 2>/dev/null
update-initramfs -v -c -k `uname -r` -b /mnt/tmpboot/
EOF1

umount --recursive ${crfsvol}
mv /mnt/tmpboot/initrd.img-`uname -r` /mnt/tmpboot/initrd.img
echo "done."

# Restore local backup of fstab
mv /etc/fstab.prev /etc/fstab

# Reboot now. Should reboot into encrypted SD card root file system.
echo "Rebooting..."
reboot

EOF
}

mk_SD_crfs_svc()
{
cat > /etc/systemd/system/cfg_SD_crfs.service <<"EOF"
[Unit]
Description=First time boot encrypted filesystem cfg service
After=rc-local.service

[Service]
Type=simple
EnvironmentFile=-/var/lib/zymbit/zkenv.conf
ExecStart=/usr/local/bin/cfg_SD_crfs.sh

[Install]
WantedBy=multi-user.target

EOF
}

mk_zymkey_initramfs_hook()
{
# Copy /var/lib/zymbit and all standalone zymkey utilities to initramfs
cat > /etc/initramfs-tools/hooks/zymkey_cryptfs_cfg <<"EOF"
#!/bin/sh

PREREQ=""

prereqs() {
     echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

mkdir -p ${DESTDIR}/var/lib/zymbit
cp -prf /var/lib/zymbit/* ${DESTDIR}/var/lib/zymbit
copy_exec /sbin/zkunlockifs /sbin

EOF
chmod +x /etc/initramfs-tools/hooks/zymkey_cryptfs_cfg
}

mk_update_script()
{
# Copy update helper script to /usr/sbin/update_encr_initrd
cat > /usr/sbin/update_encr_initrd <<"EOF"
#!/bin/bash

version="$1"
bootopt=""

kf="/mnt/tmpboot/kernel${vn}.img"
mkdir -p /mnt/tmpboot
mount /dev/mmcblk0p1 /mnt/tmpboot

if [ -n "${version}" ]
then
  echo "Kernel version ${version} passed in..."
fi

# Get the modifier from the running kernel version (e.g. "v7+" in "4.4.50-v7+")
kv=`uname -r`
vn=
echo "$kv" | grep '-' >/dev/null
if [ $? -eq 0 ]; then
   mod=`echo "$kv" | cut -d '-' -f 2`
   vn=$(echo "$mod" | sed 's/[^0-9]*//g')
fi

# If no version supplied, then figure it out on our own based on the currently
# running kernel
if [ -z "${version}" ]; then

   # Derive the installed kernel's version number from the correct image.
   # NOTE: since this script is meant to be run after an 'apt-get upgrade',
   #       this will not necessarily match 'uname -r'
   echo -n "Getting most recently installed kernel version..."
   sk=$(LC_ALL=C grep -a -b -o $'\x1f\x8b\x08\x00\x00\x00\x00\x00' ${kf} | cut -d ':' -f 1)
   sk=`echo ${sk} | cut -d ' ' -f 1`
   lv=`dd if=${kf} bs=1 skip=${sk} status=none | zcat -q | grep -a 'Linux version' | cut -d ' ' -f 3`
else
   rmod=`echo "$version" | cut -d '-' -f 2`
   if [ "${rmod}" != "${mod}" ]; then
     echo "Aborting update-initramfs due to request mismatching running kernel..."
     exit 0
   fi
   lv="${version}"
fi

if="initrd.img-${lv}"

# Bring the i2c drivers into initramfs
grep -q "^i2c-dev" /etc/initramfs-tools/modules || echo "i2c-dev" >> /etc/initramfs-tools/modules
grep -q "^i2c-bcm2835" /etc/initramfs-tools/modules || echo "i2c-bcm2835" >> /etc/initramfs-tools/modules
grep -q "^i2c-bcm2708" /etc/initramfs-tools/modules || echo "i2c-bcm2708" >> /etc/initramfs-tools/modules

echo -n "Updating initrd.img..."
rm /mnt/tmpboot/${if} 2>/dev/null
rm /mnt/tmpboot/initrd.img 2>/dev/null
update-initramfs -v -c -k ${lv} -b /mnt/tmpboot >/dev/null || exit
mv /mnt/tmpboot/${if} /mnt/tmpboot/initrd.img
echo "done."

EOF
chmod +x /usr/sbin/update_encr_initrd
}

mk_kernel_update_initramfs()
{
# Replace existing kernel initramfs rebuild with our own
cat > /etc/kernel/postinst.d/initramfs-tools <<"EOF"
#!/bin/sh -e

version="$1"
bootopt=""

[ -x /usr/sbin/update_encr_initrd ] || exit 0

# passing the kernel version is required
if [ -z "${version}" ]; then
    echo >&2 "W: initramfs-tools: ${DPKG_MAINTSCRIPT_PACKAGE:-kernel package} did not pass a version number"
    exit 2
fi

# absolute file name of kernel image may be passed as a second argument;
# create the initrd in the same directory
if [ -n "$2" ]; then
    bootdir=$(dirname "$2")
    bootopt="-b ${bootdir}"
fi

# avoid running multiple times
if [ -n "$DEB_MAINT_PARAMS" ]; then
    eval set -- "$DEB_MAINT_PARAMS"
    if [ -z "$1" ] || [ "$1" != "configure" ]; then
        exit 0
    fi
fi

update_encr_initrd ${version}

EOF
chmod +x /etc/kernel/postinst.d/initramfs-tools
}

install_init_cfg()
{
    echo "Installing necessary packages..."

    # Unmount the external device
    umount ${EXT_TMP_PART}

    echo "done."

    # Format the USB mass media
    echo -n "Formatting USB mass media on ${EXT_DEV}..."
    dd if=/dev/zero of=${EXT_DEV} bs=512 count=1 conv=notrunc >/dev/null || exit
    sync
    echo -e "n\np\n\n\n\nw\n" | fdisk -W always ${EXT_DEV} >/dev/null || exit

    # Make an ext4 file system on the temp root fs
    mkfs.ext4 -j ${EXT_TMP_PART} -F >/dev/null || exit

    # Mount the new file system on temp root fs
    mkdir -p ${tmpvol}
    mount ${EXT_TMP_PART} ${tmpvol} || exit

    # Write the initramfs-tools hook script
    mk_zymkey_initramfs_hook

    # Write the update script
    mk_update_script
    mk_kernel_update_initramfs

    # Tar up the original root file system on the root file system
    echo -n "Making a tarball of original root file system image..."
    tar -czpf ${tmpvol}/original_zk_root.tgz --exclude=var/lib/zymbit --one-file-system /
    echo "done."

    # Write a boot script into the temp fs that encrypts to root partition on
    # the SD card and copies the tarball back
    mk_SD_crfs_script
    chmod +x /usr/local/bin/cfg_SD_crfs.sh

    # Write a service for executing the script above
    mk_SD_crfs_svc
    systemctl enable cfg_SD_crfs

    # Disable zkifc on the current rootfs so that it will be disabled on the
    # installer partition
    systemctl disable zkifc
    systemctl disable zkbootrtc

    # Copy the original root filesystem over to the new drive
    echo -n "Creating installer partition on ${EXT_TMP_PART}..."
    rsync -axHAX --info=progress2 / ${tmpvol}
}

# Install rsync and the zymkey standalone apps
apt-get update -y
apt-get install -y zksaapps rsync || exit

# Check for an external volume
if [ ! -e ${EXT_DEV} ]
then
  echo "Storage device ${EXT_DEV} not detected"
  exit 1
fi

# Stop the zymkey interface connector
echo -n "Stopping zkifc..."
systemctl stop zkifc >/dev/null || exit
sleep 10
echo "done."

# Mount the boot partition in a safe place
mkdir -p /mnt/tmpboot
mount /dev/mmcblk0p1 /mnt/tmpboot || exit

# Find out if config.txt contains the "cmdline=" directive in lieu of the
# cmdline.txt file
cmdline=`grep "^cmdline=" /mnt/tmpboot/config.txt`
if [ $? -eq 0 ]
then
   cmdline=`echo ${cmdline} | cut -d'=' -f2`
else
   cmdline="cmdline.txt"
fi

# Check config.txt for inclusion of syscfg.txt and then check syscfg.txt
# for "cmdline="
if  grep -q "^include syscfg.txt" /mnt/tmpboot/config.txt
then
   syscfg_cmdline=`grep "^cmdline" /mnt/tmpboot/syscfg.txt`
   if [ $? -eq 0 ]
   then
      cmdline=`echo ${syscfg_cmdline} | cut -d'=' -f2`
   fi
fi

# Unmount the temporary boot device
umount ${EXT_TMP_PART} &>/dev/null

# Mount the temporary partition
mkdir -p ${tmpvol}
mount ${EXT_TMP_PART} ${tmpvol}
if [ $? != 0 ]
then
    echo "Mounting failed. Installing crypto installer on ${EXT_DEV}."
    install_init_cfg
fi

# Check for the existence of the distro tarball on the temporary root file
# system
if [ ! -f ${tmpvol}/original_zk_root.tgz ]
then
    echo "Distro tarball not found on tmp root fs. Installing crypto installer on ${EXT_DEV}."
    install_init_cfg
fi

rfs_type=`mount | grep " / " | awk '{print $5}'`
if [ "$rfs_type" != "ext4" ]
then
    echo "Root file system type is not ext4. Installing crypto installer on ${EXT_DEV}."
    install_init_cfg
fi

# Remove any stale bindings that might be on the tmproot and copy over
# the existing bindings from current root to tmproot
rm -rf ${tmpvol}/var/lib/zymbit/ 2>/dev/null
cp -rpf /var/lib/zymbit/ ${tmpvol}/var/lib/
# Copy the /etc/hosts and /etc/hostname
cp /etc/hosts ${tmpvol}/etc
cp /etc/hostname ${tmpvol}/etc
# Copy ssh keys
cp /etc/ssh/*_key* ${tmpvol}/etc/ssh

# Get the UUID of the installer partition
our_blkid=`blkid | grep ${EXT_TMP_PART}`
if [ $? -ne 0 ]
then
  echo "Could not locate temporary storage device"
  exit
fi

for kv in ${our_blkid}
do
  echo $kv | grep "PARTUUID=" >/dev/null
  if [ $? -eq 0 ]
  then
    EXT_TMP_PART_UUID=`echo $kv | cut -d'"' -f2`
  fi
done
echo "External device UUID = ${EXT_TMP_PART_UUID}"

# Configure for booting to the installer partition
sed -i "s/root=[^ ]*//" /mnt/tmpboot/${cmdline}
sed -i "s/  / /g" /mnt/tmpboot/${cmdline}
tr -d '\n' </mnt/tmpboot/${cmdline}> /tmp/${cmdline}
mv /tmp/${cmdline} /mnt/tmpboot/${cmdline}
echo " root=PARTUUID=${EXT_TMP_PART_UUID}" >> /mnt/tmpboot/${cmdline}

# Copy the existing fstab and configure the temporary root file system
cp /etc/fstab ${tmpvol}/etc
rfs=`grep " / " ${tmpvol}/etc/fstab | awk '{print $1}'`; sed -i "/$rfs/d" ${tmpvol}/etc/fstab
grep -q "^PARTUUID=${EXT_TMP_PART_UUID}" ${tmpvol}/etc/fstab || echo -e "\n# temp root fs\nPARTUUID=${EXT_TMP_PART_UUID} /             ext4    defaults,noatime  0       1" >> ${tmpvol}/etc/fstab
echo "done."

# Reboot now into instaler partition.
echo "root file sys conversion phase 1 complete."
echo "Rebooting to installer partition to start phase 2..."
reboot
