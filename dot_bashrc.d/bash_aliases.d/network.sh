# network aliases
if [ -x "$(type -p curl)" ]; then
    alias checkip='curl -sSL https://www.phrozenbyte.com/checkip.php'
    alias checkip4='curl -sSL4 https://www.phrozenbyte.com/checkip.php'
    alias checkip6='curl -sSL6 https://www.phrozenbyte.com/checkip.php'
fi

[ ! -x "$(type -p dig)" ] \
    || alias dig-short='dig +noall +question +answer'

alias ping4='ping -4'
alias ping6='ping -6'

alias ip='ip -c'
alias ip4='ip -4'
alias ip6='ip -6'
