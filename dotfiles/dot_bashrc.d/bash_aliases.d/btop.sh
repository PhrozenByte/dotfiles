# btop aliases
if [ -x "$(type -p btop)" ]; then
    [ -n "$(type -t htop)" ] || alias htop="btop"
    [ -n "$(type -t iotop)" ] || alias iotop="btop"
    [ -n "$(type -t iftop)" ] || alias iftop="btop"
fi
