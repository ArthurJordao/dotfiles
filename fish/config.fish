set -x GPG_TTY $(tty)
set -x GOPATH "$HOME/go"
set -x GOROOT "$(/opt/homebrew/bin/brew --prefix golang)/libexec"
set -x EDITOR nvim
set -x BAT_THEME "Catppuccin-latte"
set -x LS_COLORS "$(vivid generate catppuccin-latte)"
fish_add_path "/opt/homebrew/bin"
fish_add_path "$HOME/.local/bin"
fish_add_path "$HOME/.ghcup/bin"
fish_add_path "$HOME/.cache/rebar3/bin"
fish_add_path "$GOPATH/bin"
fish_add_path "$GOROOT/bin"
fish_add_path "$HOME/.config/emacs/bin"
fish_add_path "$HOME/.cargo/bin:$PATH"
direnv hook fish | source
fish_config theme choose "Catppuccin Latte"
fzf_configure_bindings --processes=\cb --directory=\cf --git_log=\ct --git_status=\cs
set -Ux FZF_DEFAULT_OPTS "\
--color=bg+:#ccd0da,bg:#eff1f5,spinner:#dc8a78,hl:#d20f39 \
--color=fg:#4c4f69,header:#d20f39,info:#8839ef,pointer:#dc8a78 \
--color=marker:#dc8a78,fg+:#4c4f69,prompt:#8839ef,hl+:#d20f39"
bind \e\[1\;2D backward-word
bind \e\[1\;2C forward-word
