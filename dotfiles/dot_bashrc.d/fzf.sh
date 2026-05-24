if [ -x "$(type -p fzf)" ]; then
    # source `fzf` fuzzy finder completions and key bindings
    eval "$(fzf --bash)"
fi
