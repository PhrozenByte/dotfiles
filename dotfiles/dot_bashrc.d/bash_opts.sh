# enable extended globbing
shopt -s extglob

# enable failglob, i.e., fail for globs that don't match any file
# sometimes nullglob is more useful, but it often has unintended side-effects
shopt -s failglob

# let bash automatically prepend cd when entering just a path
shopt -s autocd
