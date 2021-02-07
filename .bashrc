BREW_PREFIX=$(brew --prefix)
[ -n "$PS1" ] && source ~/.bash_profile


alias pip="${BREW_PREFIX}/bin/pip3"
export PATH="${BREW_PREFIX}/opt/python/libexec/bin:$PATH"
alias vi="${BREW_PREFIX}/bin/vim"
 
export CPATH=`xcrun --show-sdk-path`/usr/include

complete -C "${BREW_PREFIX}/usr/local/bin/terraform terraform"
