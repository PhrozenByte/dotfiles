# append to the history file, don't overwrite it
shopt -s histappend

# immediately append to the history file, don't wait until the terminal is closed
# optionally add `history -n` to enable live syncing accross all open terminals
export PROMPT_COMMAND=( 'history -a' "${PROMPT_COMMAND[@]}" )

# don't put duplicate lines and lines starting with spaces in the history
export HISTCONTROL=ignoreboth

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
export HISTSIZE=10000
export HISTFILESIZE=20000

# disable csh-style history expansion
set +o histexpand
