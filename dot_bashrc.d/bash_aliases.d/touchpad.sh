# enable/disable touchpad on GNOME Shell (`touchpad-{on,off,auto}` aliases)
if [ -x "$(type -p gnome-shell)" ] && [ -x "$(type -p gsettings)" ] && [ -x "$(type -p udevadm)" ]; then
    __touchpad_exists() {
        local dev
        for dev in /sys/class/input/event*; do
            if udevadm info --query=property "$dev" | grep -q '^ID_INPUT_TOUCHPAD=1$'; then
                return 0
            fi
        done
        return 1
    }

    if __touchpad_exists; then
        alias touchpad-on="gsettings set org.gnome.desktop.peripherals.touchpad send-events 'enabled'"
        alias touchpad-off="gsettings set org.gnome.desktop.peripherals.touchpad send-events 'disabled'"
        alias touchpad-auto="gsettings set org.gnome.desktop.peripherals.touchpad send-events 'disabled-on-external-mouse'"
    fi

    unset __touchpad_exists
fi
