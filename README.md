# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Bootstrap (new machine)

Everything here uses **SSH**, never HTTPS. The trick that makes that possible is step 3:
`op` hands you the SSH key *before* the first clone, so there's no chicken-and-egg
between "need the repo to get the key" and "need the key to clone the repo". With the
key already on disk, chezmoi's `ssh://` git external works on the very first pass and a
**single** `chezmoi apply` is enough.

### 0. Add the host to the repo first

`.chezmoidata.yaml` is the only file that names hosts. A host that isn't listed there
makes every template fail with `map has no entry for key "<hostname>"`. Add a row with
its `roles` and `services`, and push, **before** bootstrapping:

```yaml
hosts:
  <hostname>:
    roles: [gui, gaming]     # see CLAUDE.md for the role vocabulary
    services: []
```

### 1. Set the hostname

Must happen before `chezmoi init` — `.chezmoi.toml.tmpl` bakes `hostname` into the
generated config at init time, and it has to match the row you just added.

```bash
sudo hostnamectl set-hostname <hostname>   # Linux
sudo scutil --set HostName <hostname>      # macOS
```

### 2. Install the four prerequisites

Only these four; everything else installs itself in step 6.

```bash
# macOS
brew install chezmoi 1password-cli git gnupg

# Arch / CachyOS
sudo pacman -S --needed chezmoi 1password-cli git gnupg

# Debian / Ubuntu — chezmoi and 1password-cli need their own repos, see their docs
sudo apt install -y git gnupg
```

`gnupg` matters because `run_once_import-gpg-key.sh` runs *before* the package install
(scripts execute in alphabetical order of target name, and `import-` sorts before
`install-`), so it cannot rely on packages being there yet.

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

chezmoi rewrites these same files from the same 1Password items later, so this is
idempotent — you're just doing it early. Verify with:

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

### 6. Apply — once, and that's it

```bash
chezmoi apply --force
```

This installs packages too: the `run_once_` hooks fire on a host's **first** apply and
never again (later package additions need `just packages` — see CLAUDE.md).

One apply is enough because chezmoi runs scripts in alphabetical order of target name,
so `install-packages.sh` runs before `set-default-shell.sh` — `fish` is installed by the
time the login shell is set. Log out and back in for the new shell to take effect.

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
