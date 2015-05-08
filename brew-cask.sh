

# to maintain cask .... 
#     brew update && brew upgrade brew-cask && brew cleanup && brew cask cleanup` 


# Install native apps
brew install caskroom/cask/brew-cask
brew tap caskroom/versions

# daily
brew cask install divvy
brew cask install gyazo

# dev
brew cask install iterm2
brew cask install imagealpha
brew cask install imageoptim

# browsers
brew cask install google-chrome
brew cask install webkit-nightly --force
brew cask install chromium --force

# less often
brew cask install disk-inventory-x
