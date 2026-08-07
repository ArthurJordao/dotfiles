# Repo overview

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). The source dir is this
repo (checked out at `~/dev/personal/dotfiles`); `chezmoi apply` renders and deploys it.

Hosts share this repo, gated by roles in `.chezmoidata/hosts.yaml`:

- **`mars`** — Arch/CachyOS homelab server. Runs the self-hosted stack (containers, Caddy,
  CoreDNS, Minecraft). Also a desktop and gaming box. This is the interesting part and the
  focus of this file.
- **`neptune`** — macOS workstation, the NoRedInk work laptop (Brewfile, aerospace, hammerspoon,
  etc.). Renamed from `Arthurs-MacBook-Pro`. It's Kandji-MDM-enrolled, which can rewrite
  `ComputerName`/`LocalHostName` on check-in — `HostName` is the one chezmoi reads.
- **`mercury`** — Lenovo Legion Go handheld, CachyOS, user `arthur`. Same arch package family as
  mars, so it shares `packages/arch/*`. Roles `[gui, gaming, moonlight, emulation]`: shared
  dotfiles and GUI configs, no containers and no `/etc` deploy. Runs no hosted services. `gaming`
  carries no package file — CachyOS ships the gaming stack. `emulation` makes it the second half of
  the shared EmuDeck library (see "Emulation library sync").

## Host gating: three axes

`.chezmoidata/` is the only place hosts are named — `hosts.yaml` holds the per-host inventory,
`syncthing.yaml` the shared emulation folders. chezmoi merges every file in that directory into one
template data namespace, so templates just read `.hosts` / `.domain` / `.syncthing`. Gate on the
axis that is the actual reason a file isn't universal:

| Axis | Mechanism | Use for |
|---|---|---|
| **OS** | `.chezmoi.os`, `.chezmoi.osRelease` | platform-only things: aerospace, hammerspoon, Brewfile, `brew`/`paru`/`apt` |
| **Role** | `has "edge" $roles` | purpose — vocabulary is listed in `.chezmoidata/hosts.yaml` |
| **Placement** | `quadlets` list | podman quadlets — one instance in the fleet |

Roles compose: `gaming-mode` uses `and (has "server") (has "gaming")`. Never put OS/distro in
`roles`.

`./tools/simulate-host <host> managed` renders any host's output from any machine. It overrides
identity, not platform — `.chezmoi.os` stays local, so OS-gated branches need the real host.

Silent failures worth knowing:
- `dir/**` then `!dir/keep` in `.chezmoiignore` ignores everything. Negation needs single-star `dir/*`.
- A `.container` whose prefix is not in a host's `quadlets` deploys nowhere, no error.
- `.chezmoi.osRelease.idLike` errors under `missingkey=error` when `ID_LIKE` is absent (plain Arch),
  and `| default` can't rescue it. Use `index .chezmoi.osRelease "idLike"`.
- A Go template comment can't be indented inside its own action: `{{- /* x */ -}}` parses,
  `{{-   /* x */ -}}` is `unexpected "/" in command`. A parse error in **any** `.chezmoitemplates`
  file fails *every* template call, so the reported filename may not be the one you ran.
- **Never put `exact_` on a directory that holds user content.** chezmoi leaves unmanaged files
  alone in a normal managed directory (verified: a stray ROM survives an apply), but `exact_`
  deletes everything in the target not present in source. `exact_Emulation` would wipe the ROM
  library. `private_` is unrelated — it sets 0700/0600 permissions, and on a flatpak data dir like
  `.var/app/org.DolphinEmu.dolphin-emu/` that would be a change for no benefit.
- **Every** file in `.chezmoidata/` is loaded as template data, JSON included — so the JSON Schemas
  live in `schemas/`, not next to the YAML they describe. Putting `hosts.schema.json` in there
  merges its `title`, `type`, `$schema` and `properties` keys into the top-level namespace, where
  they silently shadow real data. Verified, not theoretical.

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

**2 and 3 — reverse proxy and DNS — are GENERATED.** You do not edit them. Declare an
`endpoints` entry under the service in `.chezmoidata/hosts.yaml` and the Caddy block, both DNS
records, and (with `public: true`) the tunnel rule all fall out of it. See "The generated
edge" below.

**2. Reverse proxy (Caddy)** — `etc/caddy/Caddyfile.tmpl`

- One block per endpoint: `<name>.arthurjordao.dev { reverse_proxy 127.0.0.1:<port> ... }` with
  TLS via the Cloudflare DNS challenge (`dns cloudflare {env.CF_API_TOKEN}`) and a JSON access
  log. `CF_API_TOKEN` comes from `etc/caddy/caddy.env.tmpl`.
- **Always `127.0.0.1`, never `localhost`.** `localhost` resolves to `::1` (IPv6) first, and
  rootless containers on the default network use **pasta**, which forwards IPv4 only — the IPv6
  connection is accepted then dropped, and Caddy returns a **502** without falling back. Only
  the music stack dodged this (custom `music.network` → netavark/rootlessport, dual-stack), so
  the bug surfaces on any standalone (pasta) container reached through Caddy. The template
  emits `127.0.0.1` whenever the serving host *is* the edge host, so this is now structural.

**3. DNS (CoreDNS, split-horizon)** — `etc/coredns/Corefile.tmpl`

- Every endpoint lands in **both** the `(local_hosts)` block (its host's `ip.lan`) and the
  `(tailscale_hosts)` block (its host's `ip.tailscale`). LAN clients and Tailscale clients each
  resolve to the right IP; everything else forwards to Cloudflare over DoT.
- Every host with an `ip` also gets its own `<hostname>.arthurjordao.dev` record for free.

## Public exposure (optional) — Cloudflare Tunnel

Most services are internal-only (the above three concerns cover LAN/Tailscale). To reach one
from the public internet, add it to the **Cloudflare Tunnel** instead of opening router ports.

- `cloudflared` runs as a **system** unit (`/etc/systemd/system/cloudflared.service`) using a
  named tunnel; its config is generated from `etc/cloudflared/config.yml.tmpl` and deployed to
  `/etc/cloudflared/config.yml` by `run_onchange_70-deploy-etc.sh.tmpl`. The tunnel's credentials
  `.json` lives only on mars (never in the repo).
- To expose a service: set `public: true` on its endpoint in `.chezmoidata/hosts.yaml` — that emits the
  `ingress:` rule above the `http_status:404` catch-all. Then create the public proxied CNAME once
  with `cloudflared tunnel route dns <tunnel-id> <hostname>`. `chezmoi apply` redeploys the config
  and restarts cloudflared.
- Tunnel routes go direct to `localhost:<port>`, bypassing Caddy (Cloudflare terminates TLS at
  its edge). Internal CoreDNS entries still win for LAN/Tailscale clients (split-horizon).
- Cloudflare's proxy caps requests at ~100 MB — fine for typical app traffic, a limit for large
  file downloads.
- **This tunnel is locally-managed — never edit it in the Cloudflare dashboard.** Adding a
  Public Hostname / config there attaches a *remote* config, which cloudflared then obeys while
  silently ignoring `config.yml` (there's no supported way to detach it — you'd have to recreate
  the tunnel, as was done to reach this state). Manage routes only via the file.

## The generated edge

The Caddyfile, Corefile and cloudflared config are **templates rendered from
`.chezmoidata/`**. There is no hand-written copy of any of them; editing `/etc` or trying to
edit a non-`.tmpl` `etc/caddy/Caddyfile` is editing a file that doesn't exist.

The data model, per host:

**Each host declares three flat lists, one per consumer.** There is no per-service grouping — a
service is not one entry, it's a line in each list that concerns it:

| List | Drives | Contents |
|---|---|---|
| `quadlets` | `.chezmoiignore` | quadlet filename **prefixes**, matched `<prefix>*` |
| `units` | `gaming-mode` `CANDIDATES` | systemd user units, **no** `.service` suffix |
| `endpoints` | Caddy, CoreDNS, cloudflared | hostnames to serve and resolve |

```yaml
mars:
  ip: {lan: 192.168.15.23, tailscale: 100.127.50.55}
  quadlets: [calibre-web-automated, immich, music, open-webui, shelfmark, teamspeak3]
  units: [immich-pod, immich-db, immich-valkey, immich-ml, immich-server,
          navidrome, slskd, soulsync, calibre-web-automated, open-webui,
          shelfmark, teamspeak3, minecraft@vanilla, minecraft@atm10-tts]
  endpoints:
    - {name: books, port: 8083, public: true}
    - {name: dns, port: 8053, scheme: https, tls_insecure: true, log: false}
    - {name: minecraft}           # no port -> DNS record only
```

**The three lists are independent, and that is the one thing that can drift.** A quadlet with no
`units` entry keeps running through gaming mode; a `units` entry with no quadlet names a unit that
will never exist; an endpoint with no quadlet is a 502. None of it errors. This was chosen
deliberately over a nested per-service shape — flat keeps each template reading exactly one list —
so the cost is real and lands on whoever edits the data.

Note the lists genuinely don't line up 1:1, which is why nesting them was awkward in the first
place: `immich` is one quadlet, five units, one endpoint; `music` is one quadlet, three units,
three endpoints; `teamspeak3` has no endpoint; `minecraft@*` are units with no quadlet; `dns` is an
endpoint with neither.

`units` must name **every** unit to restore, not just a pod. `Requires=` propagates stop to
dependents but start only to dependencies — stopping `immich-pod` takes the containers down, but
starting it alone brings up an empty pod.

Endpoint fields: `name` (required), `port` (omit ⇒ DNS-only, no Caddy block, no tunnel),
`public`, `scheme`, `tls_insecure`, `log`.

Each template reads `.hosts` directly — there is no shared helper. The Corefile also emits
`<hostname>.<domain>` for every host with an `ip`, which is why `mars`/`mercury`/`neptune` resolve
without being declared as endpoints.

Inspect any of them without applying — this is the way to review a change:

```
tools/simulate-host mars execute-template < etc/caddy/Caddyfile.tmpl
tools/simulate-host mars execute-template < etc/coredns/Corefile.tmpl
tools/simulate-host mars execute-template < etc/cloudflared/config.yml.tmpl
tools/simulate-host mars execute-template < dot_local/scripts/executable_gaming-mode.tmpl
```

Ordering is deterministic: Go ranges maps in sorted key order, so hosts come out alphabetically,
endpoints in declaration order within a host.

## Deploy flow

`etc/` is in `.chezmoiignore` (never copied to `$HOME`); instead
**`run_onchange_70-deploy-etc.sh.tmpl`** renders the Caddyfile, Corefile, cloudflared config and
`caddy.env` from their templates, installs them into `/etc` with `sudo`, and reloads caddy /
restarts coredns / restarts cloudflared. Each render goes to a staging file before `install`, so a
failing template (locked 1Password, say) can't truncate a live config. The quadlet files under
`dot_config/` deploy normally to `~/.config/...`.

**Its re-run trigger hashes the data, not just the template text.** Hashing
`include "etc/caddy/Caddyfile.tmpl"` alone would miss a `.chezmoidata/` edit, which changes the
*output* while the template bytes stay identical — so the header also carries a `# data:` hash of
`.hosts` + `.domain`. Keep that line if you touch the script.

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
| 80 | `restart-syncthing` | `syncthing` (emulation role) |

Pre-installed prerequisites: `chezmoi`, `1password-cli`, `git` (see README bootstrap).

**Adding a role that needs both a package and a unit is a chicken-and-egg.** The deployed
`~/.local/scripts/install-packages` bakes the host's roles in at render time
(`PKG_GROUPS=(common ...)`), so `just packages` cannot see a group for a role the deployed copy
predates. Re-rendering needs `chezmoi apply`, but that apply runs `50-enable-systemd-units`, which
fails without the package. Install the package by hand once (`paru -S --needed <pkg>`), then apply.
Applying first also works — `.local/...` sorts before `50-...`, so the script is re-rendered before
the failure — but it means a failed apply. Hit by `sunshine`, then by `emulation`.

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
in `.chezmoidata/hosts.yaml` relocates the whole Caddy/CoreDNS/cloudflared edge.

## Other mars pieces

- `dot_config/systemd/user/` — hand-written units: `cloudflare-ddns` (service+timer keeps the
  public A record current), `minecraft@.service.tmpl` (unit template; instances are mutually
  exclusive), and `minecraft-backup` (service+timer; daily world backup).
- **Minecraft instances are named in exactly one place**: the `minecraft@*` entries in a host's
  `units`. `gaming-mode`'s `CANDIDATES` and `minecraft@.service`'s `Conflicts=` are both derived
  from them, the latter by prefix-filtering that list. Renaming an instance is a one-line edit.
  It used to be two, and `d31cecf` is what happens when you only remember one.
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

# Emulation library sync (mars ↔ mercury)

Both hosts run **EmuDeck** with ES-DE. Syncthing shares one library between them, declared in
`.chezmoidata/syncthing.yaml` and rendered the way the edge is — there is no hand-written
`config.xml`.

Gated on the **`emulation`** role. Content flows one way from mars; saves go both ways.

## Data model

`syncthing.folders` is a **fourth flat list** alongside `quadlets`/`units`/`endpoints`, with the
same drift property: nothing errors when it disagrees with reality.

```yaml
- {id: emu-roms,      path: Emulation/roms,           mode: oneway, source: mars}
- {id: emu-save-eden, path: Emulation/storage/eden/nand/user/save, mode: twoway}
```

`mode: oneway` renders **Send Only** on `source` and **Receive Only** everywhere else, so a
non-source host structurally cannot push content back. `mode: twoway` renders Send & Receive with
simple file versioning (keep 5). Paths are home-relative and rendered as `~/<path>` — Syncthing
expands the tilde. Deliberately not `.chezmoi.homeDir`: the hosts have different usernames
(`turisa`/`arthur`), and `simulate-host` overrides identity but not platform, so `homeDir` would
render the previewing machine's home.

Each host also carries `syncthing_id`, its device ID.

## Two-phase bootstrap

A device ID is derived from a TLS cert Syncthing generates on first run, so it cannot be known in
advance:

1. `just packages` then `chezmoi apply` — installs syncthing, enables the user unit, and writes a
   config with **no** folders or devices (an empty `syncthing_id` omits them rather than emitting
   half a config).
2. Read the ID off each host, put it in `.chezmoidata/hosts.yaml`, apply again.

Device IDs are public — a hash of the cert public key — so committing them is fine. The certs
themselves never leave the host.

## Traps specific to this

- **Syncthing 2.x config lives in `~/.local/state/syncthing/`, not `~/.config/syncthing/`.** Write
  to the wrong one and Syncthing silently generates its own default instead; it looks like the
  template did not apply. That directory also holds `cert.pem`, `key.pem` and the SQLite database —
  only `config.xml` is managed.
- **`config.xml` is a `modify_` script, not a plain template — and it has to stay one.** Syncthing
  co-owns the file: it injects an `apikey`, adds a `<device>` entry for itself, migrates the schema
  version (38 → 52 on first start here, leaving a `config.xml.v38` backup), and expands every
  default into ~200 lines. A static template loses all of that on every apply and Syncthing puts it
  straight back, so the file is permanently dirty and `chezmoi diff` stops meaning anything.
  `modify_config.xml.tmpl` gets the current file on **stdin** and owns only the `<folder>` and
  top-level `<device>` elements plus a few `<options>`; everything else passes through.
  **The transform must be idempotent** — chezmoi diffs our stdout against the file on disk, so
  re-running on our own output has to be byte-identical. Verify with two passes:

  ```
  tools/simulate-host mars execute-template < dot_local/state/syncthing/modify_config.xml.tmpl > /tmp/m.py
  ssh mars.arthurjordao.dev cat .local/state/syncthing/config.xml > /tmp/live.xml
  python3 /tmp/m.py < /tmp/live.xml > /tmp/1.xml && python3 /tmp/m.py < /tmp/1.xml > /tmp/2.xml && diff /tmp/1.xml /tmp/2.xml
  ```
- Go templates render booleans as `true`/`false`; Python needs `True`/`False`. Use
  `ternary "True" "False"` when generating Python from chezmoi data.
- **`~/Emulation/saves/` is a farm of absolute symlinks**, not save data. EmuDeck points each one
  at wherever that emulator actually stores saves — inside `Emulation/storage/`, a flatpak's
  `.var/app/...`, `.local/share/...` or `.config/Ryujinx`. Syncing it would replicate 25 broken
  links (wrong username on the far side) and zero bytes. Every folder path must be **real storage
  on both hosts**.
- **`~/Emulation/roms/` is not pure content.** EmuDeck installs emulators inside it — Cemu in
  `wiiu/`, the Sega Model 2 emulator in `model2/`, launcher scripts in `emulators/`. Those are
  per-host and are excluded by `Emulation/roms/.stignore`. Write structural rules there, not a list
  of files you noticed: an early version enumerated `/model2/*.lua` and missed ~150 scripts one
  directory deeper. `just emu-sync-check` reports what is uncovered.
- **XML comments cannot contain `--`**, so the config template cannot write flags like
  a `‑‑flag` in a comment. Syncthing rejects the whole file. (The ID command is the
  `device-id` subcommand, not a flag, but the trap is general.)
- **`emu-save-dolphin`'s folder root is Dolphin's whole flatpak data dir**, so its `.stignore`
  admits only `GC/`, `Wii/` and `StateSaves/`. Each needs *two* lines (`!/GC` and `!/GC/**`):
  without the second, children fall through to the catch-all and only an empty directory syncs.
- **`gamelist.xml` is the most conflict-prone file here.** ES-DE rewrites it on exit to update
  `playcount`/`playtime`/`lastplayed`, so playing on both hosts between syncs conflicts every
  session. Low stakes, and it is also what carries favourites and the per-game emulator choice.
- ES-DE gamelists are **not valid XML** — two root elements (`<alternativeEmulator>` then
  `<gameList>`), which strict parsers reject outright. Extract the `<gameList>` fragment.

## Changing the folder list

`run_onchange_80-restart-syncthing.sh.tmpl` restarts the unit. Its trigger hashes the **data** as
well as the template, for the same reason `70-deploy-etc` does: editing
`.chezmoidata/syncthing.yaml` changes what renders while leaving the template byte-identical.

Inspect before applying:

```
tools/simulate-host mars execute-template < dot_local/state/syncthing/modify_config.xml.tmpl
tools/simulate-host mercury execute-template < dot_local/state/syncthing/modify_config.xml.tmpl
```

# Adding a new service (checklist)

1. `dot_config/containers/systemd/<svc>.container` (+ `<svc>.env.tmpl` if it needs secrets;
   add the keys to the `mars-secrets` 1Password item in vault `dotfiles`).
2. **Walk all three lists** in that host's entry in `.chezmoidata/hosts.yaml`. Nothing errors if you
   miss one — see the drift warning above.

   ```yaml
   quadlets:  [..., <svc>]                          # else nothing deploys
   units:     [..., <svc>]                          # else gaming mode ignores it
   endpoints: [..., {name: <svc>, port: <port>}]    # else it has no hostname
   ```

   `units` takes every unit the container files generate, not just one per quadlet.
   `endpoints` takes one entry per hostname — a service can have none (`teamspeak3`) or
   several (`music` → music/slskd/soulsync), and the name need not match the quadlet
   (`calibre-web-automated` → `books`).
3. Verify before applying: `./tools/simulate-host <host> managed | grep <svc>` for the quadlet,
   then the three `execute-template` commands above for the edge.
4. **(Optional — public internet access)** `public: true` on the endpoint, then on mars run
   `cloudflared tunnel route dns <tunnel-id> <svc>.arthurjordao.dev` once to create the CNAME.
   Do NOT use the dashboard (see the exposure section above).
5. On mars: `chezmoi apply` (renders and deploys /etc, reloads caddy/coredns, restarts
   cloudflared), then `systemctl --user daemon-reload && systemctl --user start <svc>.service`.

# Working in this repo

- The user runs `chezmoi apply` themselves — don't run it for them.
- `~/.config/nvim` is a **live symlink** into the repo (`dot_config/symlink_nvim.tmpl`); don't
  break it. `/nvim` is ignored so chezmoi doesn't double-copy it.
- Configs are cross-platform by default. Gate only what *costs* something — packages, units,
  `/etc` writes, secret reads, `run_once_*` scripts. An unused config on the wrong host is inert.
- The whole edge — Caddy, CoreDNS, cloudflared, `gaming-mode` — is generated from
  `.chezmoidata/`. Nothing about a service is declared in two places any more.
- Never re-create a static `etc/caddy/Caddyfile`, `etc/coredns/Corefile`,
  `etc/cloudflared/config.yml`, `dot_local/scripts/executable_gaming-mode` or
  `dot_config/systemd/user/minecraft@.service`. The `.tmpl` files are the only source; a static
  sibling would be silently ignored and drift forever.
- On a fresh Linux host, `run_once_30-set-default-shell.sh.tmpl` needs `fish` present. It's in
  `packages/arch/common.txt`, but if the shell change is skipped on first apply (packages not
  installed yet), just run `chezmoi apply` again.
