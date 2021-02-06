# copy paste this file in bit by bit.
# don't run it.
  echo "do not run this script in one go. hit ctrl-c NOW"
  read -n 1

##
## BACKUPS
##

dest="/Users/ajt/migration" # make this and ./~
cp ~/.extra $dest
cp ~/.z $dest
cp -r ~/.ssh $dest
cp ~/.gnupg $dest
cp -r ~/.tmuxinator $dest
cp /Volumes/Macintosh\ HD/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist $dest  # wifi
cp ~/Library/Preferences/net.limechat.LimeChat.plist $dest
cp ~/Library/Services $dest # automator stuff
cp -r ~/Documents $dest
cp -r ~/Desktop $dest
cp ~/.bash_history $dest # back it up for fun?
tar cf ~/migration.tar $dest

##
## new machine setup.
##


#
# homebrew!
#
# (google machines are funny so i have to do this. everyone else should use the regular thang)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

#
# install all the things
./brew.sh
./brew-cask.sh


#VIM DISTRO?!?


# github.com/jamiew/git-friendly
# the `push` command which copies the github compare URL to my clipboard is heaven
# bash < <( curl https://raw.github.com/jamiew/git-friendly/master/install.sh)


# Type `git open` to open the GitHub page or website for a repository.
npm install -g git-open

# Install virtualenvwrapper
pip3 install virtualenvwrapper

# github.com/rupa/z   - oh how i love you
git clone https://github.com/rupa/z.git ~/code/z
chmod +x ~/code/z/z.sh
# consider reusing your current .z file if possible. it's painful to rebuild :)
# z hooked up in .bash_profile


# disable itunes opening on media keys
git clone https://github.com/thebitguru/play-button-itunes-patch ~/code/play-button-itunes-patch


# for the c alias (syntax highlighted cat)
pip3 install Pygments

# GIVE ME POWERLINE
pip3 install powerline-status

# WHAT IS RUBY?!?!
curl -L https://get.rvm.io | bash

# HOW ABOUT TMUXINATOR?
gem install tmuxinator
mkdir ~/.bin/
curl -L -o ~/.bin/tmuxinator.bash https://raw.github.com/aziz/tmuxinator/master/completion/tmuxinator.bash


# change to bash 4 (installed by homebrew)
BASHPATH=$(brew --prefix)/bin/bash
sudo echo $BASHPATH >> /etc/shells
chsh -s $BASHPATH # will set for current user only.
echo $BASH_VERSION # should be 4.x not the old 3.2.X

sh .osx


# symlinks!
#   put/move git credentials into ~/.gitconfig.local
#   http://stackoverflow.com/a/13615531/89484
./symlink-setup.sh

