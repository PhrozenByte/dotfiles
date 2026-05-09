# enable lesspipe for `less`, internally using bat, GNU Source-highlight, etc.,
# or directly fall back to GNU's Source-highlight if lesspipe isn't availabe
if [ -x "$(type -p lesspipe.sh)" ]; then
    export LESSOPEN="| $(type -p lesspipe.sh) %s"
elif [ -x "$(type -p src-hilite-lesspipe.sh)" ]; then
    export LESSOPEN="| $(type -p src-hilite-lesspipe.sh) %s"
    export LESS=' -R '
fi
