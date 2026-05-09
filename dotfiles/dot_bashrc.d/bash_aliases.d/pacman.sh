#
# Arch Linux only
#

# yay aliases
if [ -x "$(type -p yay)" ]; then
    alias yay-install='yay -S --repo --needed'
    alias yay-reinstall='yay -S --repo --redownloadall --rebuildtree --answerclean All'
    #alias yay-update='yay -Sy'
    alias yay-upgrade='yay -Syu'
    alias yay-remove='yay -Rs'
    alias yay-purge='yay -Rns'
    alias yay-autoremove='yay -Qdtq | xargs -ro yay -Rs'
    alias yay-search='yay -Ss'
    alias yay-show='yay -Si'
    alias yay-clean='yay -Scc'
    alias yay-files='yay -Ql'
    alias yay-files-find='yay -F'
    alias yay-list='yay -Q'
    alias yay-list-manual='yay -Qe'
    alias yay-list-upgradable='yay -Qu'
    alias yay-list-obsolete='yay -Qdt'
    alias yay-list-aur='yay -Qm'
    alias yay-list-upgrades='sed -ne "s/^\[\(.*\)\] \[.*\] \(installed\|upgraded\|removed\) \(..*\)$/\1 \2 \3/p" /var/log/pacman.log'
    alias yay-mark-auto='yay -D --asdeps'
    alias yay-mark-manual='yay -D --asexplicit'
    alias yay-newconfigs='sudo find /etc -name "*.pacnew"'

    yay-report() {
        sudo pacreport --missing-files --unowned-files
        #sudo pacreport --backups --missing-files --unowned-files

        echo "Modified Package Files:"
        { sudo paccheck --quiet --files --file-properties --sha256sum \
            --require-mtree --db-files --backup --noextract --noupgrade 2>&1 1>&3 3>&- \
            | sed -e 's/^warning: \([a-z0-9][a-z0-9@_.+-]*\): /\1: /'; } 3>&1 \
            | sed -u 's/^/  /'
    }
fi

# makepkg aliases
if [ -x "$(type -p makepkg)" ]; then
    alias makepkg-build='makepkg -sr -cC'
    alias makepkg-install='makepkg -sr -i -cC'
    alias makepkg-update-srcinfo='makepkg --printsrcinfo > .SRCINFO'
fi
