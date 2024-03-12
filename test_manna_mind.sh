#!/bin/bash


SCRIPT_TEXT="python3 /home/pi/manna_mind/apps/"
GENERATE_SERIAL_NUM_FT232H="${SCRIPT_TEXT}measure_i2c/generate_serial_num_FT232H.py"
TEST_WIRINGS="${SCRIPT_TEXT}climate_control/tester.py test-wirings"
TEST_SCD30="${SCRIPT_TEXT}measure_i2c/tester_i2c.py test-scd30"
TEST_SCD4X="${SCRIPT_TEXT}measure_i2c/tester_i2c.py test-scd4x"
TEST_ALL_GAS_SENSOR="${SCRIPT_TEXT}measure_i2c/tester_i2c.py test-all-gas-sensor"
TEST_ACC="${SCRIPT_TEXT}measure_i2c/tester_i2c.py test-acc"
STOP_CLIMATE_CONTROL="sudo systemctl stop climate_control.service"
RESTART_CLIMATE_CONTROL="sudo systemctl restart climate_control.service"
QUERY_DATA="temperature, humidity, CO2, NO2, NH3, CO, O2, power"
INFLUX_QUERY="SELECT time, SENSOR_CODE, ${QUERY_DATA} FROM measurements_iot WHERE time < now() ORDER BY time DESC LIMIT 10"
TEST_INFLUXDB_DATA="influx -host 'localhost' -username influx_manna -password Manna1944 -precision rfc3339 -database 'local_measurements' -execute '$INFLUX_QUERY'"


# Trap Ctrl+C and handle it
trap ctrl_c INT

# Function to handle Ctrl+C
ctrl_c() {
    echo ""
    echo "Returning to the menu..."
    sleep 1
    exit 1
}


show_text() {
    echo ""
    echo $1
    echo ""
}

menu_selection=""
while [ "$menu_selection" != "8" ]
do  
    echo "-------------------------------------------------"
    echo "|                   TEST MENU                   |"
    echo "-------------------------------------------------"
    echo "| Please select an option and press enter:      |"
    echo "| 1. Create Serial Number for FT232h            |"
    echo "| 2. Test Wirings for climate control           |"
    echo "| 3. Test Sensor-SCD30                          |"
    echo "| 4. Test Sensor-SCD4X                          |"
    echo "| 5. Test All Gas Sensor                        |"
    echo "| 6. Test ACC                                   |"
    echo "| 7. Test Post Installation Influxdb Data       |"
    echo "| 8. Quit                                       |"
    echo "-------------------------------------------------"

    read menu_selection
    echo "-------------------------------------------------"

    case $menu_selection in
        1)
            $GENERATE_SERIAL_NUM_FT232H
            ;;
        2)  
            $STOP_CLIMATE_CONTROL
            sleep 2
            $TEST_WIRINGS
            [ $? -ne 0 ] && show_text "Failed. May be system need to reboot to get env variables"\
            || $RESTART_CLIMATE_CONTROL
            ;;
        3)
            $TEST_SCD30
            ;;
        4)
            $TEST_SCD4X
            ;;
        5)
            $TEST_ALL_GAS_SENSOR
            ;;
        6)
            $TEST_ACC
            ;;
        7)
            eval "$TEST_INFLUXDB_DATA"
            sleep 2
            ;;
        8)
            show_text "Tesing done. Going back to main menu"
            sleep 1
            ;;
        *)
            show_text "Invalid option selected"
            ;;
    esac
done