set -x GPG_TTY $(tty)
set -x GOPATH "$HOME/go"
set -x GOROOT "$(/opt/homebrew/bin/brew --prefix golang)/libexec"
set -x EDITOR nvim
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
