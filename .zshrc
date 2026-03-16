# ~/.zshrc — clean zsh config for macOS (2026)
# No plugin managers. Just zsh doing zsh things.

# ─── Homebrew ────────────────────────────────────────────────────────
if [[ "$(uname -m)" == "arm64" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ─── History ─────────────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt inc_append_history     # write to history immediately
setopt share_history          # share across sessions
setopt hist_ignore_dups       # no consecutive duplicates
setopt hist_ignore_all_dups   # remove older duplicate
setopt hist_reduce_blanks     # trim whitespace
setopt hist_ignore_space      # ignore commands starting with space

# ─── Key bindings ────────────────────────────────────────────────────
bindkey -v                    # vim mode
bindkey '^R' history-incremental-search-backward
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^P' up-history
bindkey '^N' down-history

# reduce mode switch delay
export KEYTIMEOUT=1

# ─── Completion ──────────────────────────────────────────────────────
autoload -Uz compinit
# only regenerate .zcompdump once per day
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

# ─── Options ─────────────────────────────────────────────────────────
setopt auto_cd                # cd by typing directory name
setopt auto_pushd             # push dirs onto stack
setopt pushd_ignore_dups
setopt correct                # spelling correction for commands
setopt nocaseglob             # case-insensitive globbing
setopt extended_glob
setopt no_beep

# ─── Load dotfiles ───────────────────────────────────────────────────
for file in ~/.{exports,aliases,functions,extra}; do
  [[ -r "$file" ]] && source "$file"
done
unset file

# ─── Prompt (pure) ───────────────────────────────────────────────────
# install: brew install pure
fpath+=("$(brew --prefix)/share/zsh/site-functions")
autoload -U promptinit; promptinit
prompt pure
export PURE_GIT_UNTRACKED_DIRTY=0

# ─── Plugins (manual, no manager needed) ─────────────────────────────
# install: brew install zsh-autosuggestions zsh-syntax-highlighting
[[ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# ─── z (directory jumping) ───────────────────────────────────────────
# install: brew install z
[[ -f "$(brew --prefix)/etc/profile.d/z.sh" ]] && \
  source "$(brew --prefix)/etc/profile.d/z.sh"

# ─── fzf ─────────────────────────────────────────────────────────────
# install: brew install fzf && $(brew --prefix)/opt/fzf/install
[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh

# ─── NVM (lazy load for speed) ──────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
nvm() {
  unset -f nvm node npm npx
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm "$@"
}
node() { nvm --version > /dev/null 2>&1; unset -f node; node "$@"; }
npm()  { nvm --version > /dev/null 2>&1; unset -f npm;  npm "$@"; }
npx()  { nvm --version > /dev/null 2>&1; unset -f npx;  npx "$@"; }

# ─── Python (uv) ────────────────────────────────────────────────────
# uv handles venvs and Python versions — no pyenv/virtualenvwrapper needed
# install: brew install uv

# ─── Tailscale ──────────────────────────────────────────────────────
alias ts="tailscale"
alias tss="tailscale status"

# ─── SSH completion from ~/.ssh/config ──────────────────────────────
[[ -e "$HOME/.ssh/config" ]] && \
  hosts=($(grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2)) && \
  zstyle ':completion:*:hosts' hosts $hosts
