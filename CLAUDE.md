# Repo overview

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). The source dir is this
repo (checked out at `~/dev/personal/dotfiles`); `chezmoi apply` renders and deploys it.

Hosts share this repo, gated by roles in `.chezmoidata.yaml`:

- **`mars`** — Arch/CachyOS homelab server. Runs the self-hosted stack (containers, Caddy,
  CoreDNS, Minecraft). Also a desktop and gaming box. This is the interesting part and the
  focus of this file.
- **`neptune`** — macOS workstation, the NoRedInk work laptop (Brewfile, aerospace, hammerspoon,
  etc.). Renamed from `Arthurs-MacBook-Pro`. It's Kandji-MDM-enrolled, which can rewrite
  `ComputerName`/`LocalHostName` on check-in — `HostName` is the one chezmoi reads.
- **`mercury`** — Lenovo Legion Go handheld, CachyOS, user `arthur`. Same arch package family as
  mars, so it shares `packages/arch/*`. Roles `[gui, gaming]`: shared dotfiles and GUI configs, no
  containers, units, or `/etc` deploy. Runs no hosted services. `gaming` carries no package file —
  CachyOS ships the gaming stack.

## Host gating: three axes

`.chezmoidata.yaml` is the only file that names hosts. Gate on the axis that is the actual reason
a file isn't universal:

| Axis | Mechanism | Use for |
|---|---|---|
| **OS** | `.chezmoi.os`, `.chezmoi.osRelease` | platform-only things: aerospace, hammerspoon, Brewfile, `brew`/`paru`/`apt` |
| **Role** | `has "edge" $roles` | purpose — vocabulary is listed in `.chezmoidata.yaml` |
| **Placement** | `services` list | podman quadlets — one instance in the fleet |

Roles compose: `gaming-mode` uses `and (has "server") (has "gaming")`. Never put OS/distro in
`roles`.

`./tools/simulate-host <host> managed` renders any host's output from any machine. It overrides
identity, not platform — `.chezmoi.os` stays local, so OS-gated branches need the real host.

Silent failures worth knowing:
- `dir/**` then `!dir/keep` in `.chezmoiignore` ignores everything. Negation needs single-star `dir/*`.
- A `.container` not listed in a host's `services` deploys nowhere, no error.
- `.chezmoi.osRelease.idLike` errors under `missingkey=error` when `ID_LIKE` is absent (plain Arch),
  and `| default` can't rescue it. Use `index .chezmoi.osRelease "idLike"`.

# The mars self-hosted stack

Everything runs **rootless podman** as user `turisa`. Container-root inside a rootless
container maps to `turisa` on the host, so services that must write host-owned dirs run as
uid/gid 0 (see the music stack). Fixed facts:

- Host user: `turisa` · LAN IP `192.168.15.23` · Tailscale IP `100.127.50.55`
- Base domain: `arthurjordao.dev`; every service is exposed as `<service>.arthurjordao.dev`
- Bulk media/storage SSD mounted at `/mnt/x9pro`
- Secrets: 1Password item `mars-secrets` (vault `dotfiles`), pulled at apply-time via
  `onepasswordRead "op://dotfiles/mars-secrets/<FIELD>"` in `.tmpl` files

## Three concerns per service

**1. Container (podman quadlet)** — `dot_config/containers/systemd/`

- Deploys to `~/.config/containers/systemd/`, where podman's systemd generator turns each
  `.container` / `.pod` / `.network` file into a rootless **user** unit.
- Layout: root level for standalone services (`calibre-web-automated.container`,
  `open-webui.container`, `teamspeak3.container`); subdirs for service groups that share a network/pod
  (`music/` = slskd + navidrome + soulsync on `music.network`; `immich/` = a pod of
  server/db/valkey/ml plus the top-level `immich.pod`).
- Secrets go in a sibling `<service>.env.tmpl` referenced via `EnvironmentFile=`. **Do not
  use `| quote`** in these — podman's `--env-file` keeps literal quotes. `%h` expands to the
  home dir inside unit files.
- **Generated units cannot be `systemctl enable`d** ("transient or generated" error).
  Boot-start comes from `[Install] WantedBy=default.target` in the file itself. To bring one
  up: `systemctl --user daemon-reload && systemctl --user start <svc>.service`.

**2. Reverse proxy (Caddy)** — `etc/caddy/Caddyfile`

- One block per service: `<svc>.arthurjordao.dev { reverse_proxy 127.0.0.1:<port> ... }` with
  TLS via the Cloudflare DNS challenge (`dns cloudflare {env.CF_API_TOKEN}`) and a JSON access
  log. `CF_API_TOKEN` comes from `etc/caddy/caddy.env.tmpl`.
- **Always `127.0.0.1`, never `localhost`.** `localhost` resolves to `::1` (IPv6) first, and
  rootless containers on the default network use **pasta**, which forwards IPv4 only — the IPv6
  connection is accepted then dropped, and Caddy returns a **502** without falling back. Only
  the music stack dodged this (custom `music.network` → netavark/rootlessport, dual-stack), so
  the bug surfaces on any standalone (pasta) container reached through Caddy.

**3. DNS (CoreDNS, split-horizon)** — `etc/coredns/Corefile`

- Add the hostname to **both** the `(local_hosts)` block (`192.168.15.23`) and the
  `(tailscale_hosts)` block (`100.127.50.55`). LAN clients and Tailscale clients each resolve
  to the right IP; everything else forwards to Cloudflare over DoT.

## Public exposure (optional) — Cloudflare Tunnel

Most services are internal-only (the above three concerns cover LAN/Tailscale). To reach one
from the public internet, add it to the **Cloudflare Tunnel** instead of opening router ports.

- `cloudflared` runs as a **system** unit (`/etc/systemd/system/cloudflared.service`) using a
  named tunnel; its config is tracked at `etc/cloudflared/config.yml` and deployed to
  `/etc/cloudflared/config.yml` by `run_onchange_70-deploy-etc.sh.tmpl`. The tunnel's credentials
  `.json` lives only on mars (never in the repo).
- To expose a service: add an `ingress:` rule (`hostname:` + `service: http://localhost:<port>`)
  **above** the `http_status:404` catch-all, then create the public proxied CNAME once with
  `cloudflared tunnel route dns <tunnel-id> <hostname>`. `chezmoi apply` redeploys the config
  and restarts cloudflared.
- Tunnel routes go direct to `localhost:<port>`, bypassing Caddy (Cloudflare terminates TLS at
  its edge). Internal CoreDNS entries still win for LAN/Tailscale clients (split-horizon).
- Cloudflare's proxy caps requests at ~100 MB — fine for typical app traffic, a limit for large
  file downloads.
- **This tunnel is locally-managed — never edit it in the Cloudflare dashboard.** Adding a
  Public Hostname / config there attaches a *remote* config, which cloudflared then obeys while
  silently ignoring `config.yml` (there's no supported way to detach it — you'd have to recreate
  the tunnel, as was done to reach this state). Manage routes only via the file.

## Deploy flow

`etc/` is in `.chezmoiignore` (never copied to `$HOME`); instead
**`run_onchange_70-deploy-etc.sh.tmpl`** installs the Caddyfile + Corefile into `/etc` with
`sudo`, renders `caddy.env` from its template, and reloads caddy / restarts coredns. It
re-runs whenever any of those files change (sha256 in the script header). The quadlet files
under `dot_config/` deploy normally to `~/.config/...`.

`run_*` scripts execute in alphabetical target order; the numeric prefix states it explicitly.
Anything needing a package goes after 10; gaps of 10 leave room to insert.

| | Script | Needs |
|---|---|---|
| 10 | `install-packages` | — |
| 20 | `install-tpm` | `git` |
| 30 | `set-default-shell` | `fish` |
| 40 | `setup-gpg-key` | `gpg`, `op` |
| 50 | `enable-systemd-units` | units deployed |
| 60 | `set-wallpaper` | `Pictures/` deployed |
| 70 | `deploy-etc` | `caddy`, `coredns` (edge role) |

Pre-installed prerequisites: `chezmoi`, `1password-cli`, `git` (see README bootstrap).

`run_once_50-enable-systemd-units.sh.tmpl` enables only the hand-written units, gated by the role
that owns each (`ddns`, `podman`, `minecraft`) — quadlet services are generated and can't be enabled.

Note `run_once_` state is keyed on content hash (renaming is free); `run_onchange_` is keyed on
name (renaming re-runs it).

## Packages

Packages live in `packages/<family>/<group>.txt`, where family is `arch` or `debian` (derived from
`.chezmoi.osRelease`) and group is `common` plus one file per role. Missing group files are skipped,
so a role with no packages needs no file. The concatenated list is piped to `paru -S -` /
`apt-get install`, which read **one package name per line** — so no comments and no blank lines in
those files, or the name becomes an install target.

Packages install on a host's **first** apply only, via `run_once_10-install-packages.sh.tmpl`.
After that:

```
just packages    # install this host's declared packages
just upgrade     # full system upgrade first, then install declared
```

**Adding a package to a group file does nothing until you run `just packages`** — the names are read
at runtime, so the script's hash doesn't change and the hook doesn't re-fire. That is intended; do
not add per-list `sha256sum` fingerprints to make it re-fire.

The shared body is `.chezmoitemplates/install-packages.sh`, included by both the hook and
`dot_local/scripts/executable_install-packages.tmpl`.

The install is `paru -S`, never `-Syu` (partial upgrades break Arch). `just upgrade` runs `-Syu`
first, which also avoids the 404s `paru -S` hits against a stale DB. No `cleanup` counterpart on
Linux — that would mean orphan removal.

`run_onchange_70-deploy-etc.sh.tmpl` is gated on the **`edge`** role, so moving `edge` between hosts
in `.chezmoidata.yaml` relocates the whole Caddy/CoreDNS/cloudflared edge.

## Other mars pieces

- `dot_config/systemd/user/` — hand-written units: `cloudflare-ddns` (service+timer keeps the
  public A record current), `minecraft@.service` (template; instances like
  `minecraft@vanilla`, `minecraft@atm10` are mutually exclusive), and `minecraft-backup`
  (service+timer; daily world backup).
- `dot_local/scripts/executable_minecraft` — helper to keep the boot server in sync with the
  running one.
- **JDKs are pinned.** `~/minecraft/<instance>/startserver.sh` (not in this repo) hardcodes an
  absolute JVM path per instance — vanilla `/usr/lib/jvm/java-25-openjdk`, modpack 21 — so
  `packages/arch/minecraft.txt` must match. Never use `jdk-openjdk` (rolling): its directory is
  renamed on each bump and silently breaks the path. Only LTS is pinnable (8, 11, 17, 21, 25).
- `dot_local/scripts/executable_minecraft-backup` — daily tarball of the `vanilla` world tree to
  `/mnt/x9pro/minecraft-backups`, keeping the newest 3. Pauses+flushes saves via the server's
  tmux console when it's running so the snapshot is consistent. Run by `minecraft-backup.timer`.
- `dot_local/scripts/executable_gaming-mode` — `gaming-mode {on|off|status}` stops the whole
  self-hosted stack to free CPU/GPU/RAM for gaming, then restores exactly what was running.
  **Its `CANDIDATES` list must include every resource-heavy service** — add new services here.

# Adding a new service (checklist)

1. `dot_config/containers/systemd/<svc>.container` (+ `<svc>.env.tmpl` if it needs secrets;
   add the keys to the `mars-secrets` 1Password item in vault `dotfiles`).
2. Add `<svc>` to that host's `services` in `.chezmoidata.yaml` — without it nothing deploys and
   there's no error. Check: `./tools/simulate-host <host> managed | grep <svc>`.
3. Caddy block in `etc/caddy/Caddyfile` → `127.0.0.1:<port>`.
4. `<svc>.arthurjordao.dev` in **both** host blocks of `etc/coredns/Corefile`.
5. Add `<svc>.service` to `CANDIDATES` in `dot_local/scripts/executable_gaming-mode`.
6. **(Optional — public internet access)** Add an `ingress:` rule to `etc/cloudflared/config.yml`
   (`hostname:` + `service: http://localhost:<port>`) above the `http_status:404` catch-all, then
   on mars run `cloudflared tunnel route dns <tunnel-id> <svc>.arthurjordao.dev` once to create
   the CNAME. Do NOT use the dashboard (see the exposure section above).
7. On mars: `chezmoi apply` (deploys /etc, reloads caddy/coredns, restarts cloudflared), then
   `systemctl --user daemon-reload && systemctl --user start <svc>.service`.

# Working in this repo

- The user runs `chezmoi apply` themselves — don't run it for them.
- `~/.config/nvim` is a **live symlink** into the repo (`dot_config/symlink_nvim.tmpl`); don't
  break it. `/nvim` is ignored so chezmoi doesn't double-copy it.
- Configs are cross-platform by default. Gate only what *costs* something — packages, units,
  `/etc` writes, secret reads, `run_once_*` scripts. An unused config on the wrong host is inert.
- Drift risk: `gaming-mode`'s `CANDIDATES` is hand-maintained (generating it needs a
  service→unit-name map, since `immich` expands to 5 units).
- On a fresh Linux host, `run_once_30-set-default-shell.sh.tmpl` needs `fish` present. It's in
  `packages/arch/common.txt`, but if the shell change is skipped on first apply (packages not
  installed yet), just run `chezmoi apply` again.
