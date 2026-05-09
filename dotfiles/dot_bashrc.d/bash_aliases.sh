# include drop-in files in ~/.bashrc.d/bash_aliases.d directory
if [ -d "$(dirname "${BASH_SOURCE[0]}")/bash_aliases.d" ]; then
    for __bashalias_file in "$(dirname "${BASH_SOURCE[0]}")/bash_aliases.d/"*; do
        [ -f "$__bashalias_file" ] || continue
        . "$__bashalias_file"
    done
    unset __bashalias_file
fi
