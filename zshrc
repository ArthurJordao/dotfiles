export PATH=$HOME/bin:/usr/local/bin:$HOME/.local/bin:$PATH

if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"
plugins=(git fzf)

source $ZSH/oh-my-zsh.sh
export EDITOR=lvim

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

eval "$(direnv hook zsh)"
export PATH=$PATH:$HOME/.emacs.d/bin


[ -f "/Users/$HOME/.ghcup/env" ] && source "/Users/$HOME/.ghcup/env" # ghcup-env

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
