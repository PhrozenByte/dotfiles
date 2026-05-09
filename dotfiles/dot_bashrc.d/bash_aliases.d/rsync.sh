# rsync aliases
if [ -x "$(type -p rsync)" ]; then
    alias rsync='rsync -rlptS --partial -y --delete --delete-after --info flist2,progress2,remove,skip,stats2,misc2 -h'
    alias rsync-backup='rsync -goEUAXHD'
    alias rsync-backup-remote='rsync-backup -z'
fi
