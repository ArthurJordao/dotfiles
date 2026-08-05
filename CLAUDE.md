# Repo overview

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). The source dir is this
repo (checked out at `~/dev/personal/dotfiles`); `chezmoi apply` renders and deploys it.

Hosts share this repo, gated by roles in `.chezmoidata.yaml`:

- **`mars`** — Arch/CachyOS homelab server. Runs the self-hosted stack (containers, Caddy,
  CoreDNS, Minecraft). Also a desktop and gaming box. This is the interesting part and the
  focus of this file.
- **`Arthurs-MacBook-Pro`** — macOS workstation (Brewfile, aerospace, hammerspoon, etc.).

## Host gating: three axes

Gating is **role-based, not hostname-based**. `.chezmoidata.yaml` is the only file that names
hosts; it maps each hostname to `roles` (what the box is for) and `services` (which containers
live there). Templates ask capability questions, never identity questions.

Pick the axis that is the *actual* reason a file is not universal:

| Axis | Mechanism | Use for |
|---|---|---|
| **OS** | `.chezmoi.os`, `.chezmoi.osRelease` | things that only exist on a platform: aerospace, hammerspoon, Brewfile, `brew` vs `paru` vs `apt` |
| **Role** | `has "edge" $roles` | purpose: `server`, `podman`, `gui`, `gaming`, `minecraft`, `edge`, `ddns` |
| **Placement** | `services` list | services with exactly one instance in the fleet (all podman quadlets) |

Do NOT put OS/distro into `roles` — chezmoi already knows, and duplicating it creates a second
source of truth that silently disagrees after a reinstall.

Roles compose: `gaming-mode` is gated on `and (has "server") (has "gaming")`, because it is for
a box that hosts services *and* games — not for every gaming box.

`tools/simulate-host <hostname>` renders the repo's output as any host, from any machine
(read-only, throwaway destDir): `./tools/simulate-host mars managed`. It overrides **identity,
not platform** — `.chezmoi.os` stays that of the machine you run it on, so OS-gated branches
can only be verified on the real host.

**Three silent footguns:**
- In `.chezmoiignore`, `dir/**` followed by `!dir/keep` ignores **everything** — negation only
  re-includes under a single-star `dir/*`. Never "tidy" that `*` into `**`.
- Container placement is deny-by-default: a new `.container` file that is not listed in a host's
  `services` deploys nowhere, with no error.
- Templates run with `missingkey=error`, so `.chezmoi.osRelease.idLike` **errors** on a distro
  whose `os-release` omits `ID_LIKE` (plain Arch does), and `| default` cannot rescue it — a
  failed map lookup aborts before the pipe. Use `index .chezmoi.osRelease "idLike"` instead.

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
  `/etc/cloudflared/config.yml` by `run_onchange_deploy-etc.sh.tmpl`. The tunnel's credentials
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
**`run_onchange_deploy-etc.sh.tmpl`** installs the Caddyfile + Corefile into `/etc` with
`sudo`, renders `caddy.env` from its template, and reloads caddy / restarts coredns. It
re-runs whenever any of those files change (sha256 in the script header). The quadlet files
under `dot_config/` deploy normally to `~/.config/...`.

`run_once_enable-systemd-units.sh.tmpl` only enables the hand-written units
(`cloudflare-ddns`, `podman-auto-update.timer`) — quadlet services are NOT listed there
because they're generated (see above). Each unit is enabled under the role that owns it
(`ddns`, `podman`, `minecraft`), so a host gets only what it actually runs.

Packages live in `packages/<family>/<group>.txt`, where family is `arch` or `debian` (derived
from `.chezmoi.osRelease`) and group is `common` plus one file per role.
`run_once_install-packages-linux.sh.tmpl` concatenates the groups matching the host's roles;
missing group files are skipped, so a role with no packages needs no file.

`run_onchange_deploy-etc.sh.tmpl` is gated on the **`edge`** role, so moving `edge` between hosts
in `.chezmoidata.yaml` relocates the whole Caddy/CoreDNS/cloudflared edge.

## Other mars pieces

- `dot_config/systemd/user/` — hand-written units: `cloudflare-ddns` (service+timer keeps the
  public A record current), `minecraft@.service` (template; instances like
  `minecraft@vanilla`, `minecraft@atm10` are mutually exclusive), and `minecraft-backup`
  (service+timer; daily world backup).
- `dot_local/scripts/executable_minecraft` — helper to keep the boot server in sync with the
  running one.
- `dot_local/scripts/executable_minecraft-backup` — daily tarball of the `vanilla` world tree to
  `/mnt/x9pro/minecraft-backups`, keeping the newest 3. Pauses+flushes saves via the server's
  tmux console when it's running so the snapshot is consistent. Run by `minecraft-backup.timer`.
- `dot_local/scripts/executable_gaming-mode` — `gaming-mode {on|off|status}` stops the whole
  self-hosted stack to free CPU/GPU/RAM for gaming, then restores exactly what was running.
  **Its `CANDIDATES` list must include every resource-heavy service** — add new services here.

# Adding a new service (checklist)

1. `dot_config/containers/systemd/<svc>.container` (+ `<svc>.env.tmpl` if it needs secrets;
   add the keys to the `mars-secrets` 1Password item in vault `dotfiles`).
2. **Add `<svc>` to that host's `services` list in `.chezmoidata.yaml`** — without this the file
   deploys nowhere and chezmoi reports no error. Verify with
   `./tools/simulate-host <host> managed | grep <svc>`.
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
- Configs are cross-platform by default; only gate when something is genuinely host-specific,
  and gate on the axis that is the real reason (see "Host gating: three axes" above).
- Gate what *costs* something — packages, systemd units, `/etc` writes, 1Password secret reads,
  `run_once_*` scripts. An unused config file on the wrong host is inert; a conditional for it
  is churn.
- **Known drift risk:** `gaming-mode`'s `CANDIDATES` list is still hand-maintained. It could be
  generated from `.chezmoidata.yaml`, but that needs a service→unit-name mapping (`immich`
  expands to 5 units). Until then, adding a service means editing both files.
