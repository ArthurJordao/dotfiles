# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Bootstrap (new machine)

SSH only, no HTTPS. Step 3 fetches the SSH key from 1Password *before* the first clone,
which is what avoids the chicken-and-egg and keeps this to a single `chezmoi apply`.

### 0. Add the host to `.chezmoidata.yaml` and push

Otherwise every template fails with `map has no entry for key "<hostname>"`.

```yaml
hosts:
  <hostname>:
    roles: [gui, gaming]     # see CLAUDE.md for the role vocabulary
    services: []
```

### 1. Set the hostname

Before `chezmoi init`, which bakes it into the generated config. Must match step 0.

```bash
sudo hostnamectl set-hostname <hostname>   # Linux
sudo scutil --set HostName <hostname>      # macOS
```

### 2. Install the three prerequisites

```bash
# macOS
brew install chezmoi 1password-cli git

# Arch / CachyOS — paru, not pacman: 1password-cli is AUR-only.
# CachyOS ships paru; on stock Arch, install chezmoi and git with pacman and bootstrap paru first.
paru -S --needed chezmoi 1password-cli git

# Debian / Ubuntu — chezmoi and 1password-cli need their own repos, see their docs
sudo apt install -y git
```

Everything else, `fish` and `gnupg` included, is a declared package installed in step 6.

### 3. Sign in to 1Password, then fetch the SSH keys

```bash
# Desktop machines: enabling the desktop-app CLI integration (Settings → Developer)
# is enough. Headless boxes: add the account once, then sign in.
op account add   # first time only: sign-in address, email, Secret Key, password
eval "$(op signin)"          # bash/zsh
# eval (op signin)           # fish

mkdir -p ~/.ssh && chmod 700 ~/.ssh
op read "op://dotfiles/ssh-ed25519/private" > ~/.ssh/id_ed25519 && chmod 600 ~/.ssh/id_ed25519
op read "op://dotfiles/ssh-rsa/private"     > ~/.ssh/id_rsa     && chmod 600 ~/.ssh/id_rsa
ssh-keyscan github.com >> ~/.ssh/known_hosts   # skips the interactive host-key prompt
```

chezmoi rewrites these from the same items later, so doing it early is harmless.

```bash
ssh -T git@github.com   # expect: "Hi <user>! You've successfully authenticated"
```

### 4. Clone over SSH

```bash
git clone git@github.com:ArthurJordao/dotfiles ~/dev/personal/dotfiles
```

### 5. Init chezmoi

```bash
chezmoi init --source ~/dev/personal/dotfiles

# sanity-check before writing anything
chezmoi data | grep '"hostname"'                              # must match step 1
chezmoi execute-template '{{ (index .hosts .hostname).roles }}'
chezmoi diff | head -40
```

### 6. Apply — once

```bash
chezmoi apply --force
```

Packages install here too, via the `run_once_` hooks. They fire on a host's first apply
only; later additions need `just packages`. Log out and back in for the new login shell.

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
