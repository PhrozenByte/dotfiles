if [ -x "$(type -p less)" ]; then
    # enable lesspipe for `less`, internally using bat, GNU Source-highlight, etc.,
    # or fall back to plain GNU's Source-highlight if lesspipe isn't availabe
    if [ -x "$(type -p lesspipe.sh)" ]; then
        export LESSOPEN="|- $(type -p lesspipe.sh) %s"
        export LESSQUIET=1
    elif [ -x "$(type -p src-hilite-lesspipe.sh)" ]; then
        export LESSOPEN="| $(type -p src-hilite-lesspipe.sh) %s"
    fi

    # quit if contents fit into one screen (-F), enable raw ANSI colors (-R), and use a more verbose prompt (-M)
    # different from typical defaults, don't restore the last shown screen (no -X)
    export LESS='-FRM'
fi
