# Copy paste this file in bit by bit.
# Don't run it as a script.
  echo "Do not run this script in one go. Hit ctrl-c NOW"
  read -n 1


##############################################################################################################
### Rosetta 2 (for Apple Silicon)

if [[ "$(uname -m)" == "arm64" ]]; then
  if ! /usr/bin/pgrep -q oahd; then
    echo "Installing Rosetta 2..."
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  else
    echo "Rosetta 2 is already installed."
  fi
fi


##############################################################################################################
### Backup from old machine
### (run this on the OLD machine first, then transfer ~/migration to the new one)

dest="$HOME/migration"
mkdir -p "$dest"

cp ~/.extra "$dest/" 2>/dev/null
cp ~/.gitignore_global "$dest/" 2>/dev/null
cp ~/.z "$dest/" 2>/dev/null
cp ~/.zsh_history "$dest/" 2>/dev/null
cp ~/.bash_history "$dest/" 2>/dev/null
cp -r ~/.ssh "$dest/"
cp -r ~/.gnupg "$dest/" 2>/dev/null
cp -r ~/.tmuxinator "$dest/" 2>/dev/null

# .config (app configs not tracked in dotfiles repo)
cp -r ~/.config "$dest/" 2>/dev/null

# wifi passwords
sudo cp /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist "$dest/"

# MailMate (key bindings, smart mailboxes, preferences)
mkdir -p "$dest/MailMate"
cp -r ~/Library/Application\ Support/MailMate/ "$dest/MailMate/" 2>/dev/null
cp ~/Library/Preferences/com.freron.MailMate.plist "$dest/MailMate/" 2>/dev/null

# Hazel (folder rules and preferences)
mkdir -p "$dest/Hazel"
cp -r ~/Library/Application\ Support/Hazel/ "$dest/Hazel/" 2>/dev/null
cp ~/Library/Preferences/com.noodlesoft.Hazel.plist "$dest/Hazel/" 2>/dev/null

# brew leaves for comparison
brew leaves > "$dest/brew-list.txt" 2>/dev/null
npm list -g --depth=0 > "$dest/npm-g-list.txt" 2>/dev/null

echo "Backup complete in $dest"
echo "Transfer this to the new machine and continue below."


##############################################################################################################
### XCode Command Line Tools

if ! xcode-select --print-path &>/dev/null; then
  echo "Installing XCode Command Line Tools..."
  xcode-select --install
  echo "Wait for installation to complete, then continue."
  read -p "Press enter when done..."
fi


##############################################################################################################
### Homebrew

if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # add to PATH immediately
  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# install all packages
chmod +x brew.sh brew-cask.sh
./brew.sh
./brew-cask.sh


##############################################################################################################
### Shell setup

# set zsh (Homebrew's, not system) as default shell
ZSHPATH="$(brew --prefix)/bin/zsh"
if ! grep -q "$ZSHPATH" /etc/shells; then
  echo "$ZSHPATH" | sudo tee -a /etc/shells
fi
chsh -s "$ZSHPATH"


##############################################################################################################
### Node (via nvm)

export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"
nvm install --lts
nvm use --lts

# global npm packages
npm install -g git-open
npm install -g trash-cli


##############################################################################################################
### Python (via uv)

# uv is already installed via brew.sh
# create a default Python environment if needed
uv python install 3.12


##############################################################################################################
### Git setup

# git-friendly: the `push` command that copies compare URL is great
# bash < <(curl https://raw.github.com/jamiew/git-friendly/master/install.sh)

# set up delta (already installed via brew.sh, configured in .gitconfig)

# restore git credentials
# cp ~/migration/.gitconfig.local ~/.gitconfig.local


##############################################################################################################
### Restore from backup

if [ -d "$HOME/migration" ]; then
  echo "Restoring from migration backup..."

  # SSH keys
  [ -d ~/migration/.ssh ] && cp -r ~/migration/.ssh ~/.ssh && chmod 700 ~/.ssh && chmod 600 ~/.ssh/*

  # GPG keys
  [ -d ~/migration/.gnupg ] && cp -r ~/migration/.gnupg ~/.gnupg

  # shell history
  [ -f ~/migration/.zsh_history ] && cp ~/migration/.zsh_history ~/.zsh_history
  [ -f ~/migration/.z ] && cp ~/migration/.z ~/.z

  # extra (secrets, local PATH, etc)
  [ -f ~/migration/.extra ] && cp ~/migration/.extra ~/.extra
  [ -f ~/migration/.gitignore_global ] && cp ~/migration/.gitignore_global ~/.gitignore_global

  # tmuxinator layouts
  [ -d ~/migration/.tmuxinator ] && cp -r ~/migration/.tmuxinator ~/.tmuxinator

  # .config (app configs)
  [ -d ~/migration/.config ] && cp -r ~/migration/.config ~/.config

  # MailMate (run after MailMate has been opened once to create its dirs)
  if [ -d ~/migration/MailMate ]; then
    echo "  MailMate config found. Open MailMate once first, then run:"
    echo "    cp -r ~/migration/MailMate/KeyBindings/ ~/Library/Application\ Support/MailMate/KeyBindings/"
    echo "    cp ~/migration/MailMate/com.freron.MailMate.plist ~/Library/Preferences/"
  fi

  # Hazel (run after Hazel has been opened once)
  if [ -d ~/migration/Hazel ]; then
    echo "  Hazel config found. Open Hazel once first, quit it, then run:"
    echo "    cp -r ~/migration/Hazel/ ~/Library/Application\ Support/Hazel/"
    echo "    cp ~/migration/Hazel/com.noodlesoft.Hazel.plist ~/Library/Preferences/"
  fi

  echo "Restore complete. Check ~/migration for anything else you need."
fi


##############################################################################################################
### Claude Code

# install via npm (already have node from nvm above)
npm install -g @anthropic-ai/claude-code


##############################################################################################################
### Tailscale

# installed via brew cask or from Mac App Store
# authenticate:
#   tailscale up


##############################################################################################################
### macOS defaults

# only run the subset you actually want — the old .osx file was 39KB of mostly broken defaults
# see .macos for the curated set
[ -f .macos ] && sh .macos


##############################################################################################################
### Symlinks

./symlink-setup.sh

echo ""
echo "┌──────────────────────────────────────┐"
echo "│  Setup complete!                     │"
echo "│                                      │"
echo "│  Don't forget:                       │"
echo "│  • Copy .gitconfig.local             │"
echo "│  • Set up .extra with secrets/PATHs  │"
echo "│  • tailscale up                      │"
echo "│  • Log into 1Password, Spotify, etc  │"
echo "│  • Import GPG keys if needed         │"
echo "│  • Restart terminal                  │"
echo "└──────────────────────────────────────┘"
