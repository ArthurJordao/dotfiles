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
    roles: [gui, gaming]
    ip:
      lan: 192.168.15.x
      tailscale: 100.x.x.x
```

`roles` is required — `.chezmoiignore` reads it unguarded, so omitting it fails with
`map has no entry for key "roles"`. Everything else is optional; omit what the host
doesn't need. See [Host configuration](#host-configuration) for what each one does.

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

## Host configuration

`.chezmoidata.yaml` is the only file that names hosts. Everything host-specific is
gated on what's declared there.

### Roles

What the box is *for*. Unknown names are silently inert, never an error.

| Role | Effect |
|---|---|
| `server` | long-lived hosted services |
| `podman` | deploys the rootless podman quadlets in `quadlets` |
| `gui` | graphical session configs |
| `gaming` | used for games; with `server`, also installs `gaming-mode` |
| `minecraft` | `minecraft@` units, backup timer, helper scripts |
| `edge` | owns Caddy, CoreDNS, cloudflared and the `/etc` deploy |
| `ddns` | `cloudflare-ddns` service + timer |

Roles compose, and moving one between hosts relocates what it carries — put `edge`
on a different host and the whole reverse-proxy/DNS layer moves with it.

### The three lists

Caddy, CoreDNS, the Cloudflare Tunnel and `gaming-mode` are all **generated** from
these at apply time. There is no hand-written copy of any of them.

| List | Consumer | Contents |
|---|---|---|
| `quadlets` | which container files deploy | quadlet filename *prefixes*, matched `<prefix>*` |
| `units` | `gaming-mode` | systemd user units, **without** `.service` |
| `endpoints` | Caddy, CoreDNS, cloudflared | hostnames to serve and resolve |

They're independent, and **nothing errors when they disagree** — a quadlet missing
from `units` keeps running through gaming mode, and a `units` entry with no quadlet
names a unit that will never exist. They also don't line up one-to-one: `immich` is
one quadlet, five units and one endpoint; `music` is one quadlet, three units and
three endpoints; `minecraft@vanilla` is a unit with no quadlet.

`units` must name *every* unit to restore, not just a pod. `Requires=` propagates
stop to dependents but start only to dependencies, so stopping `immich-pod` takes
its containers down while starting it alone brings up an empty pod.

### Endpoint fields

Only `name` is required. `<name>` is prefixed onto the `domain` key.

| Field | |
|---|---|
| `name` | `<name>.arthurjordao.dev` is the full hostname |
| `port` | omit for a DNS record with no reverse-proxy block |
| `public` | `true` adds a Cloudflare Tunnel ingress rule (public internet) |
| `scheme` | `https` when the upstream itself speaks TLS |
| `tls_insecure` | `true` skips verification of the upstream's certificate |
| `log` | `false` disables the JSON access log |

Every host with an `ip` also gets `<hostname>.arthurjordao.dev` for free, resolving
to `ip.lan` for LAN clients and `ip.tailscale` for tailnet clients.

### Editor validation

`chezmoidata.schema.json` describes the shape above, and `.chezmoidata.yaml` opens
with a `# yaml-language-server: $schema=` modeline pointing at it, so Neovim
validates as you type and shows each field's meaning on hover. It catches the
mistakes that otherwise fail *silently*: a misspelled `tls-insecure` currently reads
as absent and quietly disables the flag, `endpoint:` instead of `endpoints:` yields
no endpoints at all, and a typo'd role is inert by design.

It validates structure only. It cannot know that a quadlet is missing from `units`,
that a port is wrong, or that an IP points at the wrong machine.

Adding a field to a template means adding it to the schema too, or valid data starts
getting rejected.

### Reviewing a change

`etc/` is never copied to `$HOME`; the configs are rendered into `/etc` during
`apply`. To see what a change produces without applying it — from any machine, for
any host:

```bash
tools/simulate-host mars managed                  # files that would deploy
tools/simulate-host mars execute-template < etc/caddy/Caddyfile.tmpl
tools/simulate-host mars execute-template < etc/coredns/Corefile.tmpl
tools/simulate-host mars execute-template < etc/cloudflared/config.yml.tmpl
tools/simulate-host mars execute-template < dot_local/scripts/executable_gaming-mode.tmpl
```

It overrides identity, not platform: `.chezmoi.os` stays that of the machine you run
it on, so OS-gated branches need the real host.

## Secrets

Secrets are managed via 1Password (vault `dotfiles`, read with `op` at apply-time).
Items: `dotfiles-secrets`, `mars-secrets`, `ssh-ed25519`, `ssh-rsa` (Secure Notes) and
`gpg-key` (Document).

## Day-to-day

```bash
just apply       # Apply dotfiles from the local source dir
just update      # Pull from the remote first, then apply (= chezmoi update)
just packages    # Install this host's declared packages
just upgrade     # Full system upgrade, then install declared packages
just tpm-update  # Update tmux plugins
```

`apply` and `update` differ by exactly one thing: `update` runs `git pull --autostash --rebase`
in the source dir first. On the machine you author from, that rebases whatever you have in
flight — reach for `apply` while you're iterating locally.

Both sign in to 1Password first if `op whoami` says you aren't, since applying reads
`secrets.fish` and the SSH keys.
