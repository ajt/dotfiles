export HOMEBREW_CASK_OPTS="--appdir=/Applications"

# to maintain cask .... 
#     brew update && brew upgrade brew-cask && brew cleanup && brew cask cleanup` 


# Install native apps
brew install caskroom/cask/brew-cask
brew tap caskroom/versions

# daily
brew cask install divvy
brew cask install gyazo
brew cask install karabiner
brew cask install seil
brew cask install spotify
brew cask install balsamiq-mockups
brew cask install electric-sheep
brew cask install evernote
brew cask install skitch
brew cask install mailmate
brew cask install skype

# dev
brew cask install iterm2
brew cask install imagealpha
brew cask install imageoptim
brew cask install postgres

# browsers
brew cask install google-chrome
brew cask install webkit-nightly --force
brew cask install chromium --force

# less often
brew cask install disk-inventory-x

echo "Security: https://objective-see.com/products.html"
