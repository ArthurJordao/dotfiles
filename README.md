# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Bootstrap (new machine)

```bash
# 1. Clone the repo
git clone https://github.com/arthurjordao/dotfiles ~/dev/personal/dotfiles

# 2. Install chezmoi
brew install chezmoi   # macOS
pacman -S chezmoi      # Arch/CachyOS

# 3. Sign in to 1Password CLI
#    Laptop: just enable the desktop-app CLI integration (Settings → Developer).
#    mars (or any headless box): add the account once, then sign in.
op account add   # first time only: sign-in address, email, Secret Key, password
op signin

# 4. Init chezmoi (sets sourceDir in config)
chezmoi init --source ~/dev/personal/dotfiles

# 5. Deploy files first (SSH keys need to land before git externals can clone)
chezmoi apply --exclude=externals,scripts --force

# 6. Full apply (externals + scripts now work with SSH keys in place).
#    This also installs packages: the run_once_ hooks fire on a host's first
#    apply. They never re-fire afterwards — later package additions need
#    `just packages`.
chezmoi apply --force

# 7. If fish didn't become the login shell (it needs fish installed, which only
#    happened during step 6's package install), re-run:
chezmoi apply --force
```

## Secrets

Secrets are managed via 1Password (vault `dotfiles`, read with `op` at apply-time).
Items: `dotfiles-secrets`, `mars-secrets`, `ssh-ed25519`, `ssh-rsa` (Secure Notes) and
`gpg-key` (Document).

## Day-to-day

```bash
just apply       # Apply dotfiles
just packages    # Install this host's declared packages
just upgrade     # Full system upgrade, then install declared packages
just tpm-update  # Update tmux plugins
just update      # Full update
```
