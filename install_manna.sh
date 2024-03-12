#!/bin/bash

CHECK_ENCRYPTION=$(lsblk -o type | grep crypt | wc -l)
CONFIG_FILE="/etc/manna/device_config.json"
ENCRYPT_SERVICE_STATUS=$(sudo systemctl status cfg_SD_crfs.service 2>/dev/null)
ENCRYPT_SCRIPT_PID=$(pidof -x "mk_encr_sd_rfs.sh")


if [[ -n $ENCRYPT_SERVICE_STATUS ]] || [[ -n $ENCRYPT_SCRIPT_PID ]]; then
    echo "Encryption in progress, exiting"
    exit 0
fi

if [ $CHECK_ENCRYPTION -eq 1 ]; then
    echo "Encryption found"
else
    echo "Encryption not found, Insert at least 64GB empty USB stick for encryption"
    read -rp "Press 1 for encryption" USER_INPUT
    [[ "$USER_INPUT" == "1" ]] && sudo ./encrypt_image.sh
fi

if [ -f $CONFIG_FILE ]; then
    echo "manna installed"
else
    echo "manna is not install, Do you want to install manna mind?"
    read -rp "Press 2 for installation" INSTALLATION_INPUT
    if [[ "$INSTALLATION_INPUT" == "2" ]]; then
        ./register_manna_mind.sh
        ./install_manna_mind.sh
    else
        echo "Invalid input. Exiting."
        exit 1
    fi
fi
