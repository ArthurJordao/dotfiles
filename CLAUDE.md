# Repo overview

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). The source dir is this
repo (checked out at `~/dev/personal/dotfiles`); `chezmoi apply` renders and deploys it.

Two hosts share this repo, gated by `.chezmoi.hostname`:

- **`mars`** — Arch/CachyOS homelab server. Runs the self-hosted stack (containers, Caddy,
  CoreDNS, Minecraft). This is the interesting part and the focus of this file.
- **`Arthurs-MacBook-Pro`** — macOS workstation (Brewfile, aerospace, hammerspoon, etc.).

Host gating lives in `.chezmoiignore` (`{{ if ne .chezmoi.hostname "mars" }}` blocks) and in
`{{ if eq .chezmoi.hostname "mars" }}` guards at the top of the `run_*` scripts. Anything
mars-only is skipped entirely on the laptop and vice-versa.

# The mars self-hosted stack

Everything runs **rootless podman** as user `turisa`. Container-root inside a rootless
container maps to `turisa` on the host, so services that must write host-owned dirs run as
uid/gid 0 (see the music stack). Fixed facts:

- Host user: `turisa` · LAN IP `192.168.15.23` · Tailscale IP `100.127.50.55`
- Base domain: `arthurjordao.dev`; every service is exposed as `<service>.arthurjordao.dev`
- Bulk media/storage SSD mounted at `/mnt/x9pro`
- Secrets: Bitwarden secure note `mars-secrets`, pulled at apply-time via
  `bitwardenFields "item" "mars-secrets"` in `.tmpl` files

## Three concerns per service

**1. Container (podman quadlet)** — `dot_config/containers/systemd/`

- Deploys to `~/.config/containers/systemd/`, where podman's systemd generator turns each
  `.container` / `.pod` / `.network` file into a rootless **user** unit.
- Layout: root level for standalone services (`kavita.container`, `open-webui.container`,
  `teamspeak3.container`); subdirs for service groups that share a network/pod
  (`music/` = slskd + navidrome + soulsync on `music.network`; `immich/` = a pod of
  server/db/valkey/ml plus the top-level `immich.pod`).
- Secrets go in a sibling `<service>.env.tmpl` referenced via `EnvironmentFile=`. **Do not
  use `| quote`** in these — podman's `--env-file` keeps literal quotes. `%h` expands to the
  home dir inside unit files.
- **Generated units cannot be `systemctl enable`d** ("transient or generated" error).
  Boot-start comes from `[Install] WantedBy=default.target` in the file itself. To bring one
  up: `systemctl --user daemon-reload && systemctl --user start <svc>.service`.

**2. Reverse proxy (Caddy)** — `etc/caddy/Caddyfile`

- One block per service: `<svc>.arthurjordao.dev { reverse_proxy localhost:<port> ... }` with
  TLS via the Cloudflare DNS challenge (`dns cloudflare {env.CF_API_TOKEN}`) and a JSON access
  log. `CF_API_TOKEN` comes from `etc/caddy/caddy.env.tmpl`.

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

## Deploy flow

`etc/` is in `.chezmoiignore` (never copied to `$HOME`); instead
**`run_onchange_deploy-etc.sh.tmpl`** installs the Caddyfile + Corefile into `/etc` with
`sudo`, renders `caddy.env` from its template, and reloads caddy / restarts coredns. It
re-runs whenever any of those files change (sha256 in the script header). The quadlet files
under `dot_config/` deploy normally to `~/.config/...`.

`run_once_enable-systemd-units.sh.tmpl` only enables the hand-written units
(`cloudflare-ddns`, `podman-auto-update.timer`) — quadlet services are NOT listed there
because they're generated (see above).

## Other mars pieces

- `dot_config/systemd/user/` — hand-written units: `cloudflare-ddns` (service+timer keeps the
  public A record current) and `minecraft@.service` (template; instances like
  `minecraft@vanilla`, `minecraft@atm10` are mutually exclusive).
- `dot_local/scripts/executable_minecraft` — helper to keep the boot server in sync with the
  running one.
- `dot_local/scripts/executable_gaming-mode` — `gaming-mode {on|off|status}` stops the whole
  self-hosted stack to free CPU/GPU/RAM for gaming, then restores exactly what was running.
  **Its `CANDIDATES` list must include every resource-heavy service** — add new services here.

# Adding a new service (checklist)

1. `dot_config/containers/systemd/<svc>.container` (+ `<svc>.env.tmpl` if it needs secrets;
   add the keys to the `mars-secrets` Bitwarden note).
2. Caddy block in `etc/caddy/Caddyfile` → `localhost:<port>`.
3. `<svc>.arthurjordao.dev` in **both** host blocks of `etc/coredns/Corefile`.
4. Add `<svc>.service` to `CANDIDATES` in `dot_local/scripts/executable_gaming-mode`.
5. On mars: `chezmoi apply` (deploys /etc + reloads caddy/coredns), then
   `systemctl --user daemon-reload && systemctl --user start <svc>.service`.

# Working in this repo

- The user runs `chezmoi apply` themselves — don't run it for them.
- `~/.config/nvim` is a **live symlink** into the repo (`dot_config/symlink_nvim.tmpl`); don't
  break it. `/nvim` is ignored so chezmoi doesn't double-copy it.
- Configs are cross-platform by default; only gate on hostname/OS when something is genuinely
  host-specific.
