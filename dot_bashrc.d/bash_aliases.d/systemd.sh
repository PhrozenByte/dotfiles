# systemd aliases
if [ -x "$(type -p systemctl)" ]; then
    alias systemctl='systemctl --no-pager'

    #export SYSTEMD_PAGER=
    export SYSTEMD_LESS='FRXK'
fi

[ ! -x "$(type -p journalctl)" ] \
    || alias journalctl='journalctl --pager-end --lines all'
[ ! -x "$(type -p run0)" ] \
    || alias run0='run0 --shell-prompt-prefix= --background='
