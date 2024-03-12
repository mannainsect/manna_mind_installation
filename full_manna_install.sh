#!/bin/bash


DEVICE_REBOOT="sudo reboot"
DEVICE_SHUTDOWN="sudo i2cset -y 1 0x14 0x62 30 225 i && sudo shutdown -h now"

show_text() {
    echo ""
    echo $1
    echo ""
}

menu_selection=""
while [ "$menu_selection" != "6" ]
do  
    echo "-------------------------------------------------"
    echo "|               MANNA MIND MENU                 |"
    echo "-------------------------------------------------"
    echo "| Please select an option and press enter:      |"
    echo "| 1. Register To Cloud                          |"
    echo "| 2. Install Manna Mind                         |"
    echo "| 3. Test Device                                |"
    echo "| 4. Reboot                                     |"
    echo "| 5. Device Full Shutdown                       |"
    echo "| 6. Quit                                       |"
    echo "-------------------------------------------------"

    read menu_selection
    echo "-------------------------------------------------"

    case $menu_selection in
        1)
            show_text "Register device to the cloud."
            show_text "press Ctrl+C to interrupt the script."
            ./register_manna_mind.sh
            ;;
        2)
            show_text "Installing..."
            ./install_manna_mind.sh
            ;;
        3)
            show_text "Welcome to Test Menu..."
            ./test_manna_mind.sh
            ;;
        4)
            show_text "Reboot..."
            $DEVICE_REBOOT
            break
            ;;
        5)
            show_text "Shuting down in 30 seconds"
            $DEVICE_SHUTDOWN
            break
            ;;
        6)
            show_text "Exiting... Goodbye!"
            ;;
        *)
            show_text "Invalid option selected"
            ;;
    esac
done