# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Setup

```bash
# Install chezmoi and apply dotfiles
chezmoi init --apply arthurjordao
```

## Secrets

Secrets are managed via Bitwarden. Create a secure note named `dotfiles-secrets` with custom fields for each API key before applying.

```bash
bw login
```

## Day-to-day

```bash
# Apply dotfiles after editing
just apply

# Upgrade Homebrew packages and casks
just upgrade

# Update tmux plugins
just tpm-update

# Full update
just update
```
