# ls aliases
alias ll='ls -hl --group-directories-first'
alias lla='ll -a'
alias llA='ll -A'

lld() { ls -hl --color=always "$@" | grep --color=never ^d; }
llda() { ls -ahl --color=always "$@" | grep --color=never ^d; }

# grep aliases
alias grep='grep --exclude-dir .git'
alias fgrep='fgrep --exclude-dir .git'
alias egrep='egrep --exclude-dir .git'

# diff aliases
alias diff='diff --exclude .git'
[ ! -x "$(type -p colordiff)" ] \
    || alias diff='colordiff --exclude .git'

# cksum aliases
alias cksum-c='cksum --quiet --check'
alias b2sum-c='b2sum --quiet --check'
alias md5sum-c='md5sum --quiet --check'
alias sha1sum-c='sha1sum --quiet --check'
alias sha224sum-c='sha224sum --quiet --check'
alias sha256sum-c='sha256sum --quiet --check'
alias sha384sum-c='sha384sum --quiet --check'
alias sha512sum-c='sha512sum --quiet --check'

# misc coreutils aliases
alias du='du --max-depth=1 -h'
alias df='df --sync --print-type --exclude-type overlay --exclude-type squashfs --exclude-type fuse.unionfs --exclude-type fuse.unionfs-fuse --exclude-type fuse.bindfs --exclude-type tmpfs --exclude-type devtmpfs --exclude-type efivarfs -h'
alias tailf='tail -n 0 -f'

# combined mkdir and cd shortcut
mcd() {
    mkdir "$@" && cd "${@: -1}"
}

# cd to realpath
cdr() {
    cd "$(realpath "${1:-.}")"
}
