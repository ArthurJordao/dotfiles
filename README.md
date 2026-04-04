# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Bootstrap (new machine)

```bash
# 1. Clone the repo
git clone https://github.com/arthurjordao/dotfiles ~/dev/personal/dotfiles

# 2. Install chezmoi
brew install chezmoi   # macOS
pacman -S chezmoi      # Arch/CachyOS

# 3. Unlock Bitwarden
bw login
export BW_SESSION="$(bw unlock --raw)"

# 4. Init chezmoi (sets sourceDir in config)
chezmoi init --source ~/dev/personal/dotfiles

# 5. Deploy files first (SSH keys need to land before git externals can clone)
chezmoi apply --exclude=externals,scripts --force

# 6. Full apply (externals + scripts now work with SSH keys in place)
chezmoi apply --force
```

## Secrets

Secrets are managed via Bitwarden. Secure notes: `dotfiles-secrets`, `mars-secrets`, `ssh-ed25519`, `ssh-rsa`, `gpg-key`.

## Day-to-day

```bash
just apply       # Apply dotfiles
just upgrade     # Upgrade Homebrew packages and casks
just tpm-update  # Update tmux plugins
just update      # Full update
```
