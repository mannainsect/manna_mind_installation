#!/bin/bash


SENSOR_CODE_LIST=$(jq -r '.SENSOR_CONFIGURATION[].SENSOR_CODE' "$CONFIG_FILE" | tr '\n' ',' | sed 's/,$//;s/,/, /g')


echo -e "Which sensor config you want to remove?\n"
echo -e "$SENSOR_CODE_LIST\n"

while true; do
    read -p "Insert sensor code name (exm: SCD30_1): " USER_INPUT
    USER_INPUT=${USER_INPUT^^}
    if echo "$SENSOR_CODE_LIST" | grep -q -w "$USER_INPUT"; then
        break
    else
        echo "Invalid sensor code. Please try again."
    fi
done

sudo sh -c "jq --arg input \"$USER_INPUT\" '.SENSOR_CONFIGURATION |= map(select(.SENSOR_CODE != \$input))' \"$CONFIG_FILE\" > output.json && mv output.json \"$CONFIG_FILE\"" && echo 'Deletion success'
