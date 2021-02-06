[ -n "$PS1" ] && source ~/.bash_profile


alias pip=/usr/local/bin/pip3
export PATH=/usr/local/opt/python/libexec/bin:$PATH
alias vi=/usr/local/bin/vim
 
export CPATH=`xcrun --show-sdk-path`/usr/include

complete -C /usr/local/bin/terraform terraform
