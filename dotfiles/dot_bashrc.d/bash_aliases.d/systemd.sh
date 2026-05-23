if [ -x "$(type -p systemctl)" ]; then
    # disable systemctl's pager by default
    alias systemctl='systemctl --no-pager'

    # quit if contents fit into one screen (-F), enable raw ANSI colors (-R), and use a more verbose prompt (-M)
    # also exit immediately on ^C (-K), Systemd is rarely paging a stream output
    # different from typical `less` defaults, don't restore the last shown screen (no -X)
    export SYSTEMD_LESS='FRMK'
fi

[ ! -x "$(type -p journalctl)" ] \
    || alias journalctl='journalctl --boot --lines all'
[ ! -x "$(type -p run0)" ] \
    || alias run0='run0 --shell-prompt-prefix= --background='
