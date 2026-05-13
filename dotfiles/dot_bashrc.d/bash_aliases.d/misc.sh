[ -n "$(type -t vim)" ] \
        || alias vim='vi'

[ ! -x "$(type -p ssh)" ] \
    || alias ssh-once='ssh -o "UserKnownHostsFile=/dev/null"'

[ ! -x "$(type -p iotop)" ] \
    || alias iotop='iotop -o'

[ ! -x "$(type -p wget)" ] \
    || alias wget-dump='wget --page-requisites --span-hosts -e robots=off --convert-links'

[ ! -x "$(type -p pstree)" ] \
    || alias pstree='pstree -paln'

# clear swap
swapclear() {
    local SWAPS=()
    readarray -t SWAPS < <(swapon --show=NAME --noheadings)
    [ "${#SWAPS[@]}" -gt 0 ] || { echo "No swaps found." >&2 ; return 1 ; }

    swapoff "${SWAPS[@]}"
    swapon "${SWAPS[@]}"
    return $?
}

# watch iostat
if [ -x "$(type -p iostat)" ]; then
    iostat-watch() {
        local IOSTAT=( iostat --human "$@" 10 2 )
        local AWK=( awk 'NR<=2 || found {print} !/^$/ {lines=0} /^$/ {lines++} lines>=2 {found=1}' )
        watch -n0 -- "$(quote "${IOSTAT[@]}") | $(quote "${AWK[@]}")"
    }
fi

# print block device to ATA port mappings
blkata() {
    (( $# > 0 )) || set -- /sys/block/sd?

    local DEVICE= HOST= TARGET= ATA2= ATA=
    for DEVICE in "$@"; do
        DEVICE="$(basename "$DEVICE")"
        [ -e "/sys/block/$DEVICE" ] || { echo "Invalid device: $DEVICE" >&2; continue; }

        HOST="$(ls -l "/sys/block/$DEVICE" | grep -Eo 'host[0-9]+')"
        TARGET="$(ls -l "/sys/block/$DEVICE" | grep -Eo 'target[0-9:]*')"
        ATA2="$(echo "$TARGET" | grep -Eo '[0-9]:[0-9]$' | sed 's/://')"
        ATA="$(cat "/sys/class/scsi_host/$HOST/unique_id")"
        echo "$DEVICE -> ata$ATA.$ATA2"
    done
}
