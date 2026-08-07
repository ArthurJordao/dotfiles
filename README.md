# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Bootstrap (new machine)

The first clone is over HTTPS — the repo is public, so there's no chicken-and-egg
needing SSH keys (which live in 1Password) before there's anything to read them
with. `chezmoi apply` writes those keys, and a script then flips the source-dir
remote to SSH once they actually work. That flip is mostly for honesty, not
function: `dot_config/git/config`'s `insteadOf` rule already rewrites any HTTPS
remote to SSH transparently once it's deployed, so pushes go over SSH either way
— the script just makes the configured remote match what's actually happening.

### 0. Add the host to `.chezmoidata/hosts.yaml` and push

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

### 2. Install chezmoi

Everything else needed to read this repo — `1password-cli` included — installs
itself: chezmoi's `read-source-state.pre` hook runs `.install-password-manager.sh`
the first time source state is read, and the rest are declared packages installed
in step 6.

```bash
# macOS
brew install chezmoi

# Arch / CachyOS — CachyOS ships paru; on stock Arch, bootstrap paru first.
paru -S --needed chezmoi git

# Debian / Ubuntu — chezmoi needs its own repo, see its docs
sudo apt install -y git
```

### 3. Clone and initialise

```bash
chezmoi init --source ~/dev/personal/dotfiles https://github.com/ArthurJordao/dotfiles
```

Use the full URL, not chezmoi's `ArthurJordao` shorthand — that expands to
`https://user@github.com/user/dotfiles.git`, with a username embedded, which
prompts for credentials.

### 4. Check it resolved — and let the hook install the 1Password CLI

Bare `chezmoi init` clones and generates the config but never reads source
state, so the hook above hasn't fired yet. This is the first command that does
read source state, which is why it doubles as the trigger:

```bash
chezmoi data | grep '"hostname"'                              # must match step 1
chezmoi execute-template '{{ (index .hosts .hostname).roles }}'
```

Don't "simplify" this by moving it below the signin step — it has to run first
for the hook to fire before anything needs `op` to already be signed in.

`chezmoi init --apply` would collapse steps 3 and 6 into one, and it does fire
the hook, but don't use it here: apply reads secrets from 1Password, and at
this point nothing has signed in yet.

### 5. Sign in to 1Password

```bash
# Desktop machines: enabling the desktop-app CLI integration (Settings → Developer)
# is enough. Headless boxes: add the account once, then sign in.
op account add   # first time only: sign-in address, email, Secret Key, password
eval "$(op signin)"          # bash/zsh
# eval (op signin)           # fish
```

Sanity-check before writing anything:

```bash
chezmoi diff | head -40
```

This needs a signed-in `op` too — it renders the same secret-bearing templates
`apply` would.

### 6. Apply — once

```bash
chezmoi apply --force
```

This writes the SSH keys from 1Password and installs this host's declared
packages, via `run_onchange_10-install-packages`. It fires on this first apply,
prints what's declared but not installed, and asks before installing — answer
`y`. Later additions to `.chezmoidata/packages.yaml` re-fire it automatically on
the next apply, so there's no separate step; if you decline the prompt or apply
headlessly, `just packages` picks up the delta. This same apply also runs
`run_once_30-set-default-shell`, which changes your login shell to fish — log
out and back in for it to take effect.

This apply also runs `run_15-use-ssh-remote`, a plain `run_` script (it runs on
every apply, not just the first) that checks whether the SSH keys it just wrote
actually work and, if so, flips the source-dir remote from HTTPS to
`git@github.com:ArthurJordao/dotfiles`.

## Host configuration

`.chezmoidata/` is the only place hosts are named. Everything host-specific is
gated on what's declared there.

chezmoi reads **every** file in `.chezmoidata/` and merges them into one template
data namespace, so the split is organisational only — templates just see `.hosts`,
`.domain`, `.syncthing` and `.packages` regardless of which file each came from.

| File | Holds |
|---|---|
| `hosts.yaml` | `domain`, and the per-host inventory: roles, ip, quadlets, units, endpoints |
| `syncthing.yaml` | `syncthing.folders` — the shared emulation library, not owned by any one host |
| `packages.yaml` | `packages` — `arch`, grouped by `common` plus one key per role; `darwin`, flat |

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

A fourth list, `syncthing.folders`, lives in `.chezmoidata/syncthing.yaml` rather than
under a host, because it describes a library shared *between* hosts rather than any
one machine. It has the same property as the three below.

They're independent, and **nothing errors when they disagree** — a quadlet missing
from `units` keeps running through gaming mode, and a `units` entry with no quadlet
names a unit that will never exist. They also don't line up one-to-one: `immich` is
one quadlet, five units and one endpoint; `music` is one quadlet, three units and
three endpoints; `minecraft@vanilla` is a unit with no quadlet.

`units` must name *every* unit to restore, not just a pod. `Requires=` propagates
stop to dependents but start only to dependencies, so stopping `immich-pod` takes
its containers down while starting it alone brings up an empty pod.

### Adding an emulation host

Hosts with the `emulation` role share one EmuDeck library over Syncthing. A device ID
is derived from a TLS certificate Syncthing generates on its first run, so it can't be
known in advance — pairing is a **two-phase bootstrap**:

```sh
# 1. apply — this installs syncthing (answer y at the prompt) and starts it
#    with a config that has no folders yet
chezmoi apply

# 2. read the ID this host just generated
syncthing device-id
```

Put that value in the host's `syncthing_id` in `.chezmoidata/hosts.yaml`, push, and
`chezmoi apply` again on both hosts. The second apply renders the full folder set and
`run_onchange_80-restart-syncthing` restarts the service.

An empty `syncthing_id` is not an error — it makes the template omit folders and
devices entirely rather than emit half a config.

Device IDs are public (a hash of the certificate's public key), so committing them is
fine. The certificates themselves never leave the host.

Seed the first sync **on the LAN** — it is ~17 GB, and local discovery finds the peer
directly. Away from home it goes over Tailscale, since global discovery and relaying
are both disabled.

Check for drift at any time with `just emu-sync-check`, which reports sync conflicts,
`.stversions` growth, and emulator files inside the ROM tree that `.stignore` doesn't
cover.

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

`schemas/hosts.schema.json`, `schemas/syncthing.schema.json` and `schemas/packages.schema.json`
describe the shapes above, and each file in `.chezmoidata/` opens with a
`# yaml-language-server: $schema=` modeline pointing at its own schema
(`../schemas/hosts.schema.json`, `../schemas/syncthing.schema.json`,
`../schemas/packages.schema.json`), so Neovim validates as you type and shows each field's
meaning on hover. It catches the mistakes that otherwise fail *silently*: a misspelled
`tls-insecure` currently reads as absent and quietly disables the flag, `endpoint:` instead of
`endpoints:` yields no endpoints at all, and a typo'd role is inert by design.

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
just apply           # Apply dotfiles from the local source dir
just update          # Pull from the remote first, then apply (= chezmoi update)
just packages        # Install this host's declared packages, no prompt
just packages-check  # macOS only: report installed packages that aren't declared
just packages-prune  # macOS only: remove installed packages that aren't declared
just upgrade         # Full system upgrade, then install declared packages (macOS: installs declared first, then upgrades)
just tpm-update      # Update tmux plugins
```

`apply` and `update` differ by exactly one thing: `update` runs `git pull --autostash --rebase`
in the source dir first. On the machine you author from, that rebases whatever you have in
flight — reach for `apply` while you're iterating locally.

`packages-check` and `packages-prune` only exist on macOS — Linux has no orphan-removal
equivalent. On macOS, `upgrade` used to prune undeclared packages as part of upgrading; now it
doesn't touch undeclared packages at all — use `packages-check` to report them or
`packages-prune` to remove them.

Both sign in to 1Password first if `op whoami` says you aren't, since applying reads
`secrets.fish` and the SSH keys.
