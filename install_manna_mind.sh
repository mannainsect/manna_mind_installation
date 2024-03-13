#!/bin/bash

# CONFIG
MANNA_DIR="/home/pi/manna_mind"
APP_CONFIG_DIR="/home/pi/.manna_mind"
CONFIG_DIR="/etc/manna"
CONFIG_FILE="device_config.json"
SYSTEMD_SCRIPT_PATH="/systemd_configurations/install_control_systemd.sh"
MANNA_CLOUD_URL="https://main-bvxea6i-pr4445soispvo.eu-5.platformsh.site/api/v1"
DEVICE_SYNC_URL="${MANNA_CLOUD_URL}/device_configs"

# Change timezone to UTC
sudo timedatectl set-timezone UTC

# Step 1: Ask for device token if doesn't find
token=$(cat token.txt 2>/dev/null) || read -p "Please enter your token: " token

# remove token file
trap "rm ./token.txt" EXIT

# Create URL with the token
FULL_SYNC_URL="${DEVICE_SYNC_URL}/$token?force_config=true"

# Step 2: Make request to the endpoint and save the response
echo "Getting configuration from Manna Cloud"
response=$(curl -s "$FULL_SYNC_URL")

# Step 3: Extract github token and repository url
GITHUB_REPO=$(echo $response | jq -r '.GITHUB_REPO')
GITHUB_TOKEN=$(echo $response | jq -r '.GITHUB_TOKEN')

# Step 4: Clone the GitHub repository
# This version uses ssh passphrase
expect <<EOD
    spawn git clone $GITHUB_REPO $MANNA_DIR
	expect "Enter passphrase for key '/home/yourusername/.ssh/id_rsa':"
	send "$GITHUB_TOKEN\r"
	expect eof
EOD

# Verify that manna_mind folder was created
if [ -d "$MANNA_DIR" ]; then
    if [ -n "$(find "$MANNA_DIR" -maxdepth 0 -empty)" ]; then
        echo "The folder exists but is empty."
        exit 1
    else
        echo "Manna Mind repository installed correctly"
    fi
else
    echo "The folder does not exist."
    exit 1
fi

# Create Manna config directory and file to /etc/manna/device_config.json
sudo mkdir "${CONFIG_DIR}"
echo "$response" | jq '.' | sudo tee "${CONFIG_DIR}/${CONFIG_FILE}" >/dev/null

# Create app config folder if doesn't exist
mkdir -p "$APP_CONFIG_DIR"

# Add path details to /etc/environment for persistent env variables
if [ ! -f /etc/environment ]; then
    sudo touch /etc/environment
fi
sudo bash -c "echo 'MANNA_DIR=\"$MANNA_DIR\"' >> /etc/environment"
sudo bash -c "echo 'SYNC_CONFIG_URL=\"$SYNC_CONFIG_URL\"' >> /etc/environment"
sudo bash -c "echo 'CONFIG_FILE=\"${CONFIG_DIR}/${CONFIG_FILE}\"' >> /etc/environment"
sudo bash -c "echo 'APP_CONFIG_DIR=\"$APP_CONFIG_DIR\"' >> /etc/environment"
sudo bash -c "echo 'BLINKA_FT232H=1' >> /etc/environment"
sudo bash -c "echo 'TOKEN=\"$token\"' >> /etc/environment"

# Run pip3 to install latest requirements
sudo pip3 install -r ${MANNA_DIR}/requirements.txt
pip3 install -r ${MANNA_DIR}/requirements.txt

# Register apps to systemd timers
cd ${MANNA_DIR}/systemd_configurations/
"${MANNA_DIR}${SYSTEMD_SCRIPT_PATH}"

# hotspot configuration
cd ${MANNA_DIR}/scripts/
sudo ./configure_hotspot.sh

# Reboot to get env variables from /etc/environment
echo "Manna Mind installed succesfully - rebooting in 5 seconds"
sleep 5
sudo reboot
