#!/bin/bash

REQUEST_URL="https://main-bvxea6i-pr4445soispvo.eu-5.platformsh.site/api/v1"


prompt_input() {
    local prompt="$1"
    read -p "$prompt: " value
    echo "$value"
}

show_error_text() {
    echo ""
    echo $1
    echo "Try again!"
    echo ""
}

extract_access_token() {
    access_token_response=$(curl -s -X POST \
        "$REQUEST_URL/login" \
        -H "accept: application/json" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=&username=$USERNAME&password=$PASSWORD&scope=&client_id=&client_secret=")

    access_token=$(echo "$access_token_response" | jq -r '.access_token')
}

create_device_to_mongodb() {
    # modify data as a json format
    generate_json

    device_creation_response=$(curl -X POST \
        "$REQUEST_URL/devices" \
        -H "accept: application/json" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$json_data" 2>/dev/null)

    device_token=$(echo "$device_creation_response" | jq -r '.token')

    [ "$device_token" != "null" ] && echo "Device creation successfull." &&
        echo "$device_token" >token.txt && return 0 || return 1
}

get_token() {
    USERNAME=$(prompt_input "Admin email(required)")
    PASSWORD=$(prompt_input "Admin password(required)")
    extract_access_token

    [ "$access_token" != "null" ] && return 0 || return 1
}

generate_json() {
    json_data="{"

    [ -n "$version" ] && json_data+="\"version\": \"$version\", "
    [ -n "$device_code" ] && json_data+="\"device_code\": \"${device_code^^}\", "

    if [ -n "$ruuvi_macs_input" ]; then
        IFS=', ' read -r -a ruuvi_macs_array <<<"$ruuvi_macs_input"
        ruuvi_macs_json=$(printf '"%s",' "${ruuvi_macs_array[@]}")
        json_data+="\"ruuvi_macs\": [${ruuvi_macs_json%,}], "
    fi

    [ -n "$vint_sensor_serial" ] && json_data+="\"vint_sensor_serial\": $vint_sensor_serial, "
    [ -n "$vint_control_serial" ] && json_data+="\"vint_control_serial\": $vint_control_serial, "

    json_data="${json_data%,*}"
    json_data+="}"
}

validate_mac_address() {
    mac_address="$1"
    # Check if string length is not equal to 12
    if [ ${#mac_address} -ne 12 ]; then
        show_error_text "Invalid length of ${mac_address}"
        return 1
    fi

    # Check if string contains only hexadecimal characters
    if [[ ! "$mac_address" =~ ^[0-9a-fA-F]{12}$ ]]; then
        show_error_text "Contains non-hexadecimal characters of ${mac_address}"
        return 1
    fi

    return 0
}

validate_vint() {
    vint_type="$1"

    if [ ${#vint_type} -ne 6 ]; then
        show_error_text "Too short or long vint hub serial number $vint_type"
        return 1
    fi

    if ! [[ $vint_type =~ ^[0-9]+$ ]]; then
        show_error_text "Contains non-numeric characters $vint_type"
        return 1
    fi

    return 0
}

create_token() {
    while ! get_token; do
        res_error=$(echo "$access_token_response" | jq -r '.detail')
        show_error_text "$res_error"
    done
}

# need token for creating device
create_token

# asking version number
while ! version=$(prompt_input "Version 1.0 or 1.5(required)") ||
    ! [[ $version =~ ^1\.[05]$ ]]; do
    show_error_text "Invalid version. Please enter 1.0 or 1.5."
done

# asking device code
while ! device_code=$(prompt_input "device_code(e.g. FIMANNA0001)") ||
    [ -z "$device_code" ]; do
    show_error_text "Device Code is empty"
done

# ruuvi validation if insert ruuvi mac
while true; do
    data_insertion=$([[ "$version" == "1.0" ]] && echo "required" || echo "optional")
    ruuvi_macs_input=$(prompt_input "Ruuvi MACs (separated by spaces or commas, e.g. DCD84C0D85ED,ACE84C0D45EA) (required)")

    if [[ -z "$ruuvi_macs_input" ]]; then
        show_error_text "ruuvi macs input can't be empty"
        continue
    fi
    
    invalid_mac=false

    # Split the input string by spaces or commas
    IFS=', ' read -ra macs <<<"$ruuvi_macs_input"

    for mac in "${macs[@]}"; do
        if [[ -n "$mac" ]]; then
            if ! validate_mac_address "$mac"; then
                invalid_mac=true
            fi
        fi
    done

    if [[ "$invalid_mac" == "false" ]]; then
        # Add "ruuvi_" prefix before each Ruuvi MAC address
        ruuvi_macs_input=$(echo "${macs[@]/#/ruuvi_}" | tr ' ' ',')
        break
    fi
done

# vint validation if insert vint serial number
while true; do
    vint_sensor_serial=$(prompt_input "vint_sensor_serial($data_insertion)")
    vint_control_serial=$(prompt_input "vint_control_serial($data_insertion)")

    if [[ "$version" == "1.0" && (-z "$vint_sensor_serial" || -z "$vint_control_serial") ]]; then
        show_error_text "Empty value not allowed for version 1.0"
        continue
    fi

    if [[ -n "$vint_sensor_serial" ]]; then
        if ! validate_vint "$vint_sensor_serial"; then
            continue
        fi
    fi

    if [[ -n "$vint_control_serial" ]]; then
        if ! validate_vint "$vint_control_serial"; then
            continue
        fi
    fi

    break
done

# create device to mongodb
while ! create_device_to_mongodb; do
    device_exist="Device code already exists"
    not_authorize="Not authorized"
    device_creation_error=$(echo "$device_creation_response" | jq -r '.detail')

    if [[ "$device_creation_error" == "$not_authorize" ]]; then
        show_error_text "$device_creation_error"
        create_token
    fi

    if [[ "$device_creation_error" == "$device_exist" ]]; then
        numeric_part="${device_code: -4}"
        device_part="${device_code:0:-4}"
        # increment by 1
        ((numeric_part = 10#$numeric_part + 1))

        device_code="${device_part}$(printf "%04d" $numeric_part)"
    fi
done
