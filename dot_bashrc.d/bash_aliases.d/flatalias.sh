# flatpak aliases
if [ -x "$(type -p flatpak)" ]; then
    [ ! -f "${XDG_STATE_HOME:-$HOME/.local/state}/flatalias.profile" ] \
        || source "${XDG_STATE_HOME:-$HOME/.local/state}/flatalias.profile"

    # additional aliases
    [ "$(type -t gnome-text-editor)" != "alias" ] || [ -n "$(type -t gedit)" ] \
        || alias gedit="gnome-text-editor"
fi
