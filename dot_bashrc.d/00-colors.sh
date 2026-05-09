# enable color support for ls, dir, vdir, grep, fgrep, egrep
if [ -x "$(type -p dircolors)" ]; then
    if [ -f ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi

    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# enable color support for gcc
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# highlight stderr output
color() {
    (
        set -o pipefail
        "$@" 2>&1 >&3 | sed -u $'s/.*/\e[31m&\e[m/' >&2
    ) 3>&1
}
