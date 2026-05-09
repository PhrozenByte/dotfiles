# when `rmtrash` is installed ...
if [ -x "$(type -p rmtrash)" ]; then
    # alias `rm` to `rmtrash`
    alias rm='rmtrash --forbid-root'
else
    # without `rmtrash` installed, make `rm` a bit safer at least...
    alias rm='rm -i'
fi

# alias `rmdir` to `rmdirtrash`, if installed
[ ! -x "$(type -p rmdirtrash)" ] \
    || alias rmdir='rmdirtrash --forbid-root'
