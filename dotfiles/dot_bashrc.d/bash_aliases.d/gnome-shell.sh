# get GNOME Shell back on track (`gnome-shell-{quit,hup}` aliases)
if [ -x "$(type -p gnome-shell)" ]; then
    alias gnome-shell-quit='killall -QUIT gnome-shell'
    alias gnome-shell-hup='killall -HUP gnome-shell'
fi
