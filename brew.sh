# Install command-line tools using Homebrew

# Make sure we’re using the latest Homebrew
brew update --all

# Upgrade any already-installed formulae
brew upgrade

BREW_PREFIX=$(brew --prefix)


# Install GNU core utilities (those that come with OS X are outdated)
# Don’t forget to add `$(brew --prefix coreutils)/libexec/gnubin` to `$PATH`.
brew install coreutils
ln -s "${BREW_PREFIX}/bin/gsha256sum" "${BREW_PREFIX}/bin/sha256sum"

# Install some other useful utilities like `sponge`
brew install moreutils
# Install GNU `find`, `locate`, `updatedb`, and `xargs`, `g`-prefixed
brew install findutils
# Install GNU `sed`, overwriting the built-in `sed`
brew install gnu-sed --default-names


# Install Bash 4
# Note: don’t forget to add `/usr/local/bin/bash` to `/etc/shells` before running `chsh`.
brew install bash
brew install bash-completion2

# Switch to using brew-installed bash as default shell
if ! fgrep -q "${BREW_PREFIX}/bin/bash" /etc/shells; then
  echo "${BREW_PREFIX}/bin/bash" | sudo tee -a /etc/shells;
  chsh -s "${BREW_PREFIX}/bin/bash";
fi;


# generic colouriser  http://kassiopeia.juls.savba.sk/~garabik/software/grc/
brew install grc
brew install gnupg


# Install wget with IRI support
brew install wget --with-iri

# Install more recent versions of some OS X tools
brew install vim --override-system-vi
brew install homebrew/dupes/grep

# Install other useful binaries
brew install ack
brew install git
brew install gs
brew install p7zip

brew install imagemagick --with-webp
brew install node # This installs `npm` too using the recommended installation method
brew install pv
brew install rename
brew install tree
brew install zopfli
brew install ffmpeg --with-libvpx

# more
brew install python
brew install htop-osx
brew install irssi
brew install jpeg
brew install knock
brew install memcached
brew install mercurial
brew install p7zip
brew install sqlite
brew install ssh-copy-id
brew install subversion
brew install tmux
brew install reattach-to-user-namespace

# https://www.youtube.com/watch?v=ocmJE2O4uIU
ln -sfv /usr/local/opt/memcached/*.plist ~/Library/LaunchAgents
launchctl load ~/Library/LaunchAgents/homebrew.mxcl.memcached.plist

# Remove outdated versions from the cellar
brew cleanup


