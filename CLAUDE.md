# Repo overview

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). The source dir is this
repo (checked out at `~/dev/personal/dotfiles`); `chezmoi apply` renders and deploys it.

Hosts share this repo, gated by roles in `.chezmoidata/hosts.yaml`:

- **`mars`** — Arch/CachyOS homelab server. Runs the self-hosted stack (containers, Caddy,
  CoreDNS, Minecraft). Also a desktop and gaming box. This is the interesting part and the
  focus of this file.
- **`neptune`** — macOS workstation, the NoRedInk work laptop (Brewfile, aerospace, etc.).
  Renamed from `Arthurs-MacBook-Pro`. It's Kandji-MDM-enrolled, which can rewrite
  `ComputerName`/`LocalHostName` on check-in — `HostName` is the one chezmoi reads.
- **`mercury`** — Lenovo Legion Go handheld, CachyOS, user `arthur`. Same arch package family as
  mars, so it reads the same `packages.arch` groups. Roles `[gui, gaming, moonlight, emulation]`:
  shared dotfiles and GUI configs, no containers, no `/etc` deploy, no hosted services. `gaming`
  has no key under `packages.arch` — CachyOS ships the gaming stack. `emulation` makes it the
  second half of the shared EmuDeck library (see "Emulation library sync").

## Host gating: three axes

`.chezmoidata/` is the only place hosts are named — `hosts.yaml` holds the per-host inventory,
`syncthing.yaml` the shared emulation folders, `minecraft.yaml` the server instances and their
JDKs, `packages.yaml` the package declarations, `secrets.yaml` the 1Password vault and item names,
`cloudflare.yaml` the tunnel ID, `dns.yaml` the filter's lists and upstream. chezmoi merges every
file in that directory into one template data namespace, so templates just read `.hosts` /
`.domain` / `.syncthing` / `.minecraft` / `.packages` / `.secrets` / `.cloudflare` / `.dns`. Gate
on the axis that is the actual reason a file isn't universal:

| Axis | Mechanism | Use for |
|---|---|---|
| **OS** | `$me.os`, `$me.distro` | platform-only things: aerospace, Brewfile, `brew`/`paru`/`apt` |
| **Role** | `has "edge" $roles` | purpose — vocabulary is listed in `.chezmoidata/hosts.yaml` |
| **Placement** | `quadlets` list | podman quadlets — one instance in the fleet |

Roles compose: `gaming-mode` uses `and (has "server") (has "gaming")`. Never put OS/distro in
`roles` — they are their own fields.

**`managed: false` puts a box in the inventory without applying to it** — it gets its DNS
records and its `~/.ssh/config` block, nothing else, and declares `user`/`ip` only.
`roles`/`os`/`distro` are required on a managed host and inert on this one, and `tools/hosts`
omits it so no template is ever rendered against it. `ip` itself is optional, but declaring it
means declaring **both** `lan` and `tailscale` — every box in the inventory is on the tailnet.
Consequence for any template that iterates `.hosts`: guard every field access — `index $h
"roles" | default list`, never `$h.roles`. `europa` and `deimos` (Kindles running KOReader)
are the ones so far.

**Read `os`/`distro` from the host, never `.chezmoi.os`.** chezmoi's own value describes the
machine running the render and cannot be overridden, which is exactly what made `simulate-host`
half-blind. Every host declares `os` (and `distro` on Linux), so overriding the hostname overrides
the platform too and `./tools/simulate-host <host> managed` renders any host correctly from any
machine. 1Password calls go to `tools/mock-op` and render `mock:<FIELD>`; pass `--real-op` for
actual values.

**`managed` is not enough on its own.** It lists target paths, so a template whose `include` path
went stale still passes it and only fails during a real apply on the host. `just check` runs
everything and is what to run after moving or renaming any source file:

| | Checks |
|---|---|
| `tools/check-templates` | renders every template for every host, `.chezmoitemplates/etc/` included |
| `tools/check-schemas` | each `.chezmoidata` file against the schema its own header names |
| `tools/check-consistency` | the quadlets/units/endpoints/folders/packages cross-references |
| `tools/check-shell` | shellcheck, rendering `.tmpl` scripts per host first |

CI runs the same `tools/check` on every push. It needs no secrets.

`just check` proves the repo is self-consistent and runs anywhere. **`just check-live` runs on a
`podman` host and proves that host matches it** — declared units active and wanted at boot,
containers accounted for by a quadlet file, endpoints answering, no failed units of ours.
Read-only, no credentials. It reads `gaming-mode`'s state file, so a stopped stack reports as
intentional rather than as drift.

Silent failures worth knowing:
- **A tmux pane inherits the tmux *server's* environment, not the client's.** `Environment=` in a
  unit whose `ExecStart` is `tmux new-session` never reaches the command — only names in tmux's
  `update-environment` cross over. This is why `minecraft/atm10-tts/start` sets `ATM10_JAVA`
  itself: a script running inside the pane is unaffected. `tmux new-session -e VAR=value` also
  works if a value ever has to come from the unit.
- `dir/**` then `!dir/keep` in `.chezmoiignore` ignores everything. Negation needs single-star
  `dir/*` — though no block relies on negation any more.
- **A quadlet file no host claims deploys to *every* podman host.** The ignore names other hosts'
  quadlets to suppress them, so anything unclaimed is unignored everywhere and `exact_systemd`
  keeps it. `check-consistency` C11 is what makes that an error.
- **A bare field lookup on a key that may be absent errors under `missingkey=error`, and
  `| default` can't rescue it.** `index` yields nil there instead: a darwin host has no `distro`,
  so `.chezmoitemplates/install-packages.sh` reads `index (index .hosts .hostname) "distro"`.
- **`onepasswordItemFields` drops any field with no `section`.** It returns an empty map and every
  lookup fails with `no entry for key "value"` — the trap to know when touching `tools/mock-op`.
- A comment opening `# shellcheck ` is parsed as a **directive**, not prose, and an unparseable
  one is an error. Relevant to any script whose subject is shellcheck itself.
- A Go template comment can't be indented inside its own action: `{{- /* x */ -}}` parses,
  `{{-   /* x */ -}}` is `unexpected "/" in command`. A parse error in **any** `.chezmoitemplates`
  file fails *every* template call, so the reported filename may not be the one you ran.
- **Never put `exact_` on a directory that holds user content.** chezmoi leaves unmanaged files
  alone in a normal managed directory, but `exact_` deletes everything in the target not present
  in source — `exact_Emulation` would wipe the ROM library. `private_` is unrelated: it sets
  0700/0600, and is right only where the target really is 0700. `dot_local/state/private_syncthing/`
  needs it (syncthing sets 0700 on a directory holding `key.pem`, and without it chezmoi reports
  "has changed since chezmoi last wrote it" every apply); a flatpak data dir does not. On the
  quadlets, `exact_` goes on `systemd/` and never on `containers/` — that one is podman's own
  (`auth.json`, `containers.conf`), and nothing in it is managed.
- **`exact_` does not recurse.** Each directory level needs its own prefix — `exact_nvim/exact_lua/
  exact_plugins/`. A level without it silently keeps stray files. Files matching `.chezmoiignore`
  are exempt from `exact_` deletion.
- **A script in `.chezmoiscripts/` without `after_` runs before every file is deployed.** That
  directory name sorts ahead of `.config`, `.local`, `Brewfile` and `Pictures`, and scripts are
  ordered against target paths. `before_`/`after_` override the positional order; every script here
  is `after_`.
- **chezmoi ignores dot-prefixed files in source state**, so a `.neoconf.json` inside a managed
  directory never deploys — it must be `dot_neoconf.json`. Same rule that lets `.nvim-state/` hold
  files chezmoi must not manage, and that makes `.install-password-manager.sh` a hook, not a target.
- **Port 5353 is mDNS, and that breaks fast failover.** `avahi-daemon` holds a wildcard
  `0.0.0.0:5353`, so when a container publishing `127.0.0.1:5353` stops, that socket absorbs the
  packet instead of the kernel refusing it — `dig` reports `timed out`, not `connection refused`.
  CoreDNS's `forward` then waits out a full 2s per query until its health check marks the upstream
  down. blocky's filter port is `5533` for this reason; any replacement needs **no** other
  listener, and `15353` is reserved by convention for throwaway CoreDNS tests.
- **systemd-resolved sends private reverse lookups to mDNS and waits out the timeout** — a PTR for
  a LAN address cost mars a flat 7.7s. Fixed with `nmcli connection modify ap-not-found
  connection.llmnr 0 connection.mdns 0`. mDNS was the culprit, not LLMNR. Safe because
  `avahi-daemon` provides `.local` service discovery independently.

  **It has a second half.** Turning off resolved's mDNS removed glibc's only route to `.local`, so
  `ssh mercury.local` stopped resolving. The fix is `mdns_minimal [NOTFOUND=return]` in
  `/etc/nsswitch.conf`'s `hosts:` line, right after `mymachines`:

  ```
  hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns
  ```

  Both halves are **host config, not chezmoi-managed**, and will not survive a mars rebuild.
  Backup of the original at `/etc/nsswitch.conf.pre-mdns`.
- **Every** file in `.chezmoidata/` is loaded as template data, JSON included — so the JSON Schemas
  live in `schemas/`, not next to the YAML they describe. Putting `hosts.schema.json` in there
  merges its `title`, `type`, `$schema` and `properties` keys into the top-level namespace, where
  they silently shadow real data.
- **`.chezmoi.toml.tmpl` must never call `onepasswordRead`.** chezmoi renders the config template
  before it can learn which hooks are configured, so the `hooks.read-source-state.pre` hook
  (`.install-password-manager.sh`) cannot satisfy a dependency the config template itself needs —
  `chezmoi init` would fail with `op: executable file not found in $PATH` and no hook could rescue
  it. Related trap: the hook command is baked into the generated, unmanaged
  `~/.config/chezmoi/chezmoi.toml` as an **absolute path**. Move or re-clone the source dir and
  every chezmoi command fails with `read-source-state: pre: ...: no such file or directory`, not
  just `apply`. Recovery: edit or delete the `[hooks.read-source-state.pre]` stanza by hand, or
  re-run `chezmoi init`.

# The mars self-hosted stack

Everything runs **rootless podman** as user `turisa`. Container-root inside a rootless
container maps to `turisa` on the host, so services that must write host-owned dirs run as
uid/gid 0 (see the music stack).

**Not everything mars needs is in this repo.** `docs/unmanaged.md` is the rebuild checklist for
the rest: the hand-built `caddy` binary and its user, linger, the four `/etc/systemd/system`
units, the limine cmdline, the fstab line, and the name-resolution fix. Add to it whenever
something load-bearing is set up by hand.

Fixed facts:

- Host user: `turisa` · LAN IP `192.168.15.23` · Tailscale IP `100.127.50.55`
- Base domain: `arthurjordao.dev`; every service is exposed as `<service>.arthurjordao.dev`
- External media/storage SSD mounted at `/mnt/x9pro`, declared as `hosts.mars.storage.external`
- Secrets: one 1Password item per service, titles declared in `.chezmoidata/secrets.yaml`.
  The item is fetched **once per file** and indexed, so no title appears in a template:

  ```
  {{- $op := onepasswordItemFields .secrets.items.slskd .secrets.vault -}}
  SLSKD_USERNAME={{ (index $op "SLSKD_WEB_USERNAME").value }}
  ```

  A field name that isn't in the item fails the apply (`nil pointer evaluating
  interface {}.value`) rather than rendering empty.

## Three concerns per service

**1. Container (podman quadlet)** — `dot_config/containers/exact_systemd/`

- Deploys to `~/.config/containers/systemd/`, where podman's systemd generator turns each
  `.container` / `.pod` / `.network` file into a rootless **user** unit.
- **Every level is `exact_`**, so a file in the target that no host's `quadlets` claims is deleted
  on the next apply — that is how a retired service leaves. It removes the file, not the running
  container: stop the unit yourself.
- Layout: root level for standalone services (`calibre-web-automated.container`,
  `cloudflare-ddns.container`, `shelfmark.container`, `teamspeak3.container`); subdirs for service
  groups that share a network/pod
  (`exact_music/` = slskd + navidrome + soulsync on `music.network`; `exact_immich/` = a pod of
  server/db/valkey/ml plus the top-level `immich.pod`).
- **Mount points and the timezone are data, not per-service facts.** `{{ .timezone }}` is
  fleet-wide, read directly. Mount points are per-host under `storage` and read through a
  template — the lookup is fleet-wide like `endpoint-port`, so the quadlet renders identically
  on hosts that don't deploy it, and a name declared twice with different paths fails:

  ```
  {{- $external := includeTemplate "storage-path" (dict "hosts" .hosts "name" "external") -}}
  Volume={{ $external }}/music:/music:ro
  ```
- **Home paths use systemd's `%h`, never `/home/turisa`** — both quadlets and hand-written user
  units. One less host fact baked into a file.
- **A quadlet with a proxied port is a `.tmpl`, and its `PublishPort` host side is generated.**
  `{{ template "endpoint-port" (dict "hosts" .hosts "endpoint" "books") }}:8083` reads the port
  off that endpoint in `.chezmoidata/hosts.yaml`, so Caddy and podman cannot disagree. Only the
  host side — the container side is the image's own port and stays literal. The lookup is
  fleet-wide (endpoint names are DNS names in one zone), so the file renders identically on hosts
  that don't deploy it; an unknown endpoint name fails the apply. Ports with no endpoint stay
  literal too: slskd's Soulseek peer port, all three of teamspeak3's.
- Secrets go in a sibling `<service>.env.tmpl` referenced via `EnvironmentFile=`. **Do not
  use `| quote`** in these — podman's `--env-file` keeps literal quotes. `%h` expands to the
  home dir inside unit files.
- **The two env mechanisms quote oppositely.** An `Environment=` line is systemd syntax and
  splits on whitespace, so a value containing a space must be quoted and the quotes are
  stripped: `Environment="UPDATE_CRON=@every 15m"`. Unquoted, the container silently receives
  `@every`. In the `EnvironmentFile=` above, the same quotes would arrive literally.
- **Generated units cannot be `systemctl enable`d** ("transient or generated" error).
  Boot-start comes from `[Install] WantedBy=default.target` in the file itself. To bring one
  up: `systemctl --user daemon-reload && systemctl --user start <svc>.service`.

**2 and 3 — reverse proxy and DNS — are GENERATED.** You do not edit them. Declare an
`endpoints` entry under the service in `.chezmoidata/hosts.yaml` and the Caddy block, both DNS
records, and (with `public: true`) the tunnel rule all fall out of it. See "The generated
edge" below.

**2. Reverse proxy (Caddy)** — `.chezmoitemplates/etc/caddy/Caddyfile`

- One block per endpoint: `<name>.arthurjordao.dev { reverse_proxy 127.0.0.1:<port> ... }` with
  TLS via the Cloudflare DNS challenge (`dns cloudflare {env.CF_API_TOKEN}`) and a JSON access
  log. `CF_API_TOKEN` comes from `.chezmoitemplates/etc/caddy/caddy.env`.
- **Always `127.0.0.1`, never `localhost`.** `localhost` resolves to `::1` first, and rootless
  containers on the default network use **pasta**, which forwards IPv4 only — the connection is
  accepted then dropped, and Caddy returns a **502** without falling back. The template emits
  `127.0.0.1` whenever the serving host *is* the edge host, so this is structural.

**3. DNS (CoreDNS, split-horizon)** — `.chezmoitemplates/etc/coredns/Corefile`

- Every endpoint lands in **both** the `(local_hosts)` block (its host's `ip.lan`) and the
  `(tailscale_hosts)` block (its host's `ip.tailscale`). LAN clients and Tailscale clients each
  resolve to the right IP; everything else forwards to Cloudflare over DoT.
- Every host with an `ip` also gets its own `<hostname>.arthurjordao.dev` record for free.

## Public exposure (optional) — Cloudflare Tunnel

Most services are internal-only (the above three concerns cover LAN/Tailscale). To reach one
from the public internet, add it to the **Cloudflare Tunnel** instead of opening router ports.

- `cloudflared` runs as a **system** unit (`/etc/systemd/system/cloudflared.service`) using a
  named tunnel; its config is generated from `.chezmoitemplates/etc/cloudflared/config.yml` and
  deployed to `/etc/cloudflared/config.yml` by `run_onchange_after_70-deploy-etc.sh.tmpl`. The
  credentials `.json` lives only on mars (never in the repo).
- To expose a service: set `public: true` on its endpoint in `.chezmoidata/hosts.yaml` — that emits the
  `ingress:` rule above the `http_status:404` catch-all. Then create the public proxied CNAME once
  with `cloudflared tunnel route dns <tunnel-id> <hostname>`. `chezmoi apply` redeploys the config
  and restarts cloudflared.
- Tunnel routes go direct to `localhost:<port>`, bypassing Caddy (Cloudflare terminates TLS at
  its edge). Internal CoreDNS entries still win for LAN/Tailscale clients (split-horizon).
- Cloudflare's proxy caps requests at ~100 MB — fine for typical app traffic, a limit for large
  file downloads.
- **This tunnel is locally-managed — never edit it in the Cloudflare dashboard.** Adding a
  Public Hostname there attaches a *remote* config, which cloudflared obeys while silently
  ignoring `config.yml`, and there is no supported way to detach it. Manage routes only via
  the file.

## The generated edge

The Caddyfile, Corefile and cloudflared config are **templates rendered from
`.chezmoidata/`**, living in `.chezmoitemplates/etc/`. There is no hand-written copy of any of
them; editing `/etc` is editing a file that gets overwritten on the next apply.

The data model, per host:

**Each host declares three flat lists, one per consumer.** There is no per-service grouping — a
service is not one entry, it's a line in each list that concerns it:

| List | Drives | Contents |
|---|---|---|
| `quadlets` | `.chezmoiignore` | quadlet **names** — a top-level directory, or the stem before the first `.` |
| `units` | `gaming-mode` `CANDIDATES` | systemd user units, **no** `.service` suffix. Minecraft instances are not here — they come from `.chezmoidata/minecraft.yaml` |
| `endpoints` | Caddy, CoreDNS, cloudflared, `~/.ssh/config`, quadlet `PublishPort` | hostnames to serve and resolve |

```yaml
mars:
  os: linux
  distro: arch                    # linux only; picks the package family
  ip: {lan: 192.168.15.23, tailscale: 100.127.50.55}
  quadlets: [calibre-web-automated, cloudflare-ddns, immich, music, shelfmark, teamspeak3]
  units: [immich-pod, immich-db, immich-valkey, immich-ml, immich-server,
          navidrome, slskd, soulsync, calibre-web-automated, cloudflare-ddns,
          shelfmark, teamspeak3, syncthing]
  endpoints:
    - {name: books, port: 8083, public: true}
    - {name: dns, port: 8053, scheme: https, tls_insecure: true, log: false, served_by: coredns}
    - {name: minecraft, ddns: true}   # no port -> DNS record only; ddns keeps the A record current
```

**The three lists are independent, and that is the one thing that can drift.** A quadlet with no
`units` entry keeps running through gaming mode; a `units` entry with no quadlet names a unit that
will never exist; an endpoint with no quadlet is a 502. None of it errors. The one pair that
*can't* drift is the port: the quadlet reads it from the endpoint.

Each `units` entry is an object, `{name, stop_for_gaming}` — uniform on purpose,
so no consumer branches on the entry's type. `stop_for_gaming: false` keeps a
unit out of `gaming-mode`'s `CANDIDATES` while `check-live` still expects it
active: `olivetin`, `sunshine` and `blocky`. Never read the flag with
`| default` — sprig treats `false` as empty and flips it to `true`. `check-live`
also resolves each name to its canonical unit `Id` before asking about boot,
because an alias reports `is-enabled=alias`: `sunshine` is one, for
`app-dev.lizardbyte.app.Sunshine`, and C3 accepts the short name only because
the package is called `sunshine` too.

They don't line up 1:1: `immich` is one quadlet, five units, one endpoint; `music` is one quadlet,
three units, three endpoints; `teamspeak3` has no endpoint; `dns` is an endpoint with neither;
`minecraft` is an endpoint whose units come from `.chezmoidata/minecraft.yaml` instead.

`units` must name **every** unit to restore, not just a pod. `Requires=` propagates stop to
dependents but start only to dependencies — stopping `immich-pod` takes the containers down, but
starting it alone brings up an empty pod.

Endpoint fields: `name` (required), `port` (omit ⇒ DNS-only, no Caddy block, no tunnel),
`public`, `ddns`, `scheme`, `tls_insecure`, `log`, `served_by`.

`ddns: true` makes the `cloudflare-ddns` container keep that hostname's public A record on the
current WAN IP. Independent of `public`, which routes a hostname through the tunnel instead.

`served_by` names the non-container service listening on that port — `dns` → coredns, `sunshine` →
the package. Without it, `check-consistency` requires one of that host's quadlets to publish the
port, so the field is what separates "intentionally not a container" from "forgot the quadlet".

Each template reads `.hosts` directly — there is no shared helper. The Corefile also emits
`<hostname>.<domain>` for every host with an `ip`, which is why `mars`/`mercury`/`neptune` resolve
without being declared as endpoints.

`private_dot_ssh/private_config.tmpl` is a fifth consumer, and the only one reading the scalar
`user`: one `Host` block per host, aliased by short name, `.local`, `<host>.<domain>`, both IPs
and every endpoint of that host. `user` is required on every host, unmanaged
ones included — being reachable by name is what they are declared for. The `Host *` preamble is
the only hand-written part. Rendered identically everywhere — the block for the host you are on
is inert, not skipped.

Inspect any of them without applying — this is the way to review a change:

```
tools/render-edge --list
tools/render-edge mars caddy/Caddyfile
tools/render-edge mars coredns/Corefile
tools/render-edge mars cloudflared/config.yml
tools/simulate-host mars execute-template < dot_local/scripts/executable_gaming-mode.tmpl
```

The `/etc` bodies live in `.chezmoitemplates/etc/`, so they have no `.tmpl` to redirect into
`simulate-host`; `tools/render-edge` feeds it the `includeTemplate` call instead. To see all four
in the order they install, render the deploy script itself.

Ordering is deterministic: Go ranges maps in sorted key order, so hosts come out alphabetically,
endpoints in declaration order within a host.

## Deploy flow

**`run_onchange_after_70-deploy-etc.sh.tmpl`** carries the Caddyfile, Corefile, cloudflared config
and `caddy.env` **inline**, one quoted heredoc each via `includeTemplate`, then installs them into
`/etc` with `sudo` and reloads caddy / restarts coredns / restarts cloudflared. Each body is
written to a staging file before `install`, because `sudo tee` truncates the live config first.
The quadlet files under `dot_config/` deploy normally to `~/.config/...`.

**Inlining is what makes it correct, and it needs no hash header.** Shelling out to a nested
`chezmoi execute-template` gave the child its own `op` session and no `--config` — so an apply
needed an interactive 1Password unlock and `simulate-host` rendered these four with the *local*
hostname, silently. Rendering in the main pass fixes both, and since the configs are now part of
the script's own bytes, `run_onchange` re-fires exactly when the output changes. Add no `# data:`
hash here; `trimSuffix "\n"` on each `includeTemplate` keeps the heredoc terminator on its own
line.

All eleven scripts live in **`.chezmoiscripts/`** and every one carries the **`after_`** attribute, so
they run once every file has been deployed and the numeric prefix orders only the scripts among
themselves. Keep both properties on any new script: without `after_`, `.chezmoiscripts` sorts ahead
of `.config`, `.local`, `Brewfile` and `Pictures`, and the script runs before anything lands.
Anything needing a package goes after 10; gaps of 10 leave room to insert. Keep prefixes **two digits** — the order is lexical, so `100-` would sort before `15-`.

| | Script | Needs |
|---|---|---|
| 10 | `install-packages` | — |
| 15 | `use-ssh-remote` | — |
| 30 | `set-default-shell` | `fish` |
| 35 | `reset-bat` | — |
| 40 | `setup-gpg-key` | `gpg`, `op` |
| 50 | `enable-systemd-units` | units deployed |
| 60 | `set-wallpaper` | `Pictures/` deployed |
| 70 | `deploy-etc` | `caddy`, `coredns` (edge role) |
| 80 | `restart-syncthing` | `syncthing` (emulation role) |
| 90 | `restart-olivetin` | OliveTin config deployed (server role) |
| 95 | `restart-blocky` | blocky config deployed (claims the quadlet) |

Pre-installed prerequisites: `chezmoi` and `git`. `1password-cli` is **not** one — it installs
itself via the `hooks.read-source-state.pre` hook (`.install-password-manager.sh`) the first time
source state is read, before any template needing `op` runs.

**`.install-password-manager.sh`** drives the bootstrap and has no `run_*` slot of its own — it is
the `hooks.read-source-state.pre` hook itself. Deliberately **not** a `.tmpl` (hooks run before
chezmoi's template machinery exists, so it uses `uname`) and deliberately **dot-prefixed** (chezmoi
ignores dotfiles as source state; without the dot it would manage the script as a target). Either
change breaks it silently.

**`run_once_after_15-use-ssh-remote.sh.tmpl`** flips the source-dir remote from the bootstrap HTTPS
clone to SSH.

`run_onchange_after_10-install-packages.sh.tmpl` renders the package names into its own body, so
adding a role's key to `.chezmoidata/packages.yaml` changes that script's hash, and `10-` sorts
before `50-enable-systemd-units` — a new role's package installs in the *same* apply that enables
its unit. The catch: decline the install prompt (see "Packages"), or run headless with no TTY, and
step 50 still fails for lack of the package.

`run_once_after_50-enable-systemd-units.sh.tmpl` enables only the hand-written units, gated by the
role that owns each (`podman`, `minecraft`) — quadlet services are generated and can't be
enabled.

Note `run_once_` state is keyed on content hash (renaming is free); `run_onchange_` is keyed on
name (renaming re-runs it).

## Packages

Packages are declared in `.chezmoidata/packages.yaml` — the only place package names live. The
`arch` key is grouped by `common` plus one key per role name; a role with no key installs
nothing, which is not an error — but guard every lookup with `hasKey`, since under
`missingkey=error` a bare `.packages.arch.podman` fails the template when the key is absent. The
`darwin` key is flat, and each entry is a bare string or `{name, trusted}` where Homebrew needs
the trust flag — losing one makes `brew bundle cleanup --force` wipe `trust.json`.

**The names render *into* `run_onchange_after_10-install-packages.sh.tmpl`** (both the Linux body
and the darwin branch), so editing the YAML changes the rendered script's own hash and the hook
re-fires on the next apply. No `sha256sum` fingerprint on the data is needed — do not add one.

`chezmoi apply` prints only the delta — declared minus installed — and **asks before
installing**. Declining exits 0; chezmoi records `run_onchange` state only on success, so the
prompt won't return until the data changes again, and `just packages` is the escape hatch: it
never prompts, because running it is itself the confirmation. With no TTY (a headless apply) the
script prints the delta and exits without installing anything.

**On macOS, both the apply-time check and the apply-time install pass `brew bundle`
`--no-upgrade`.** Without it, `brew bundle check` reports merely-outdated formulae as unmet, so
apply would prompt whenever anything had drifted stale; and the install call needs the flag too,
or answering `y` to a few missing packages would silently upgrade every unrelated outdated one.
`just packages` and `just upgrade` deliberately keep the upgrading behavior — an unattended
`apply` should never surprise-upgrade something you didn't ask for.

`schemas/packages.schema.json` lives in `schemas/`, not `.chezmoidata/` — see the shadowing trap
above.

**The Brewfile is generated, so `brew bundle dump` is retired as an authoring workflow** — a
re-dump would be overwritten on the next apply and would destroy every `trusted` flag. Add
packages to the YAML by hand. `.chezmoitemplates/brewfile` is the shared body, rendered by
`Brewfile.tmpl` (deploys `~/Brewfile`) and separately by the darwin branch of
`run_onchange_after_10-install-packages.sh.tmpl`, which renders its own copy to a temp file so it
depends on no target file.

The shared body for Linux is `.chezmoitemplates/install-packages.sh`, included by both the hook
and `dot_local/scripts/executable_install-packages.tmpl` — what `just packages` runs, with no
`PROMPT` set, so it never asks.

The install is `paru -S`, never `-Syu` (partial upgrades break Arch). `just upgrade` runs `-Syu`
first, which also avoids the 404s `paru -S` hits against a stale DB. No `cleanup` counterpart on
Linux — that would mean pacman orphan removal, which isn't implemented.

```
just check           # every repo check: templates, schemas, consistency, shellcheck
just packages        # install this host's declared packages, no prompt
just packages-check  # macOS only: report installed-but-undeclared, removes nothing
just packages-prune  # macOS only: remove installed-but-undeclared
just upgrade         # full system upgrade, then install declared (macOS: installs declared first, then upgrades)
```

`run_onchange_after_70-deploy-etc.sh.tmpl` is gated on the **`edge`** role, so moving `edge` between
hosts in `.chezmoidata/hosts.yaml` relocates the whole Caddy/CoreDNS/cloudflared edge.

## Other mars pieces

- `dot_config/systemd/user/` — hand-written units: `minecraft@.service.tmpl` (unit template;
  instances are mutually exclusive) and `minecraft-backup` (service+timer; daily world backup).
- **Minecraft instances are declared in exactly one place**: `.chezmoidata/minecraft.yaml`. A host
  runs them by having the `minecraft` role — `units` carries no minecraft entries. Both
  `minecraft@.service`'s `Conflicts=` and `gaming-mode`'s `CANDIDATES` derive from that list, so
  renaming an instance is a one-line edit.
- **Every instance has a managed launcher at `~/minecraft/<instance>/start`**, and the unit runs
  `./start` for all of them — a uniform name is what keeps the shared unit template free of any
  per-instance branching. A plain Paper instance (`vanilla`, `matcha`) is one
  `includeTemplate "minecraft-paper-start"` line; `atm10-tts`'s injects the JVM and execs the
  modpack's own `startserver.sh`, which stays unmanaged because it installs NeoForge and
  writes a first-run `server.properties`. **Nothing under `minecraft/` may be `exact_`** — it
  holds worlds, mods and backups.
- `dot_local/scripts/executable_minecraft` — helper to keep the boot server in sync with the
  running one.
- **JDKs are pinned per instance** by `jdk:` in `.chezmoidata/minecraft.yaml`, which derives both
  Arch names: package `jdk21-openjdk` and path `/usr/lib/jvm/java-21-openjdk`. `check-consistency`
  C7 requires each instance's package to be declared under `packages.arch.minecraft`. Never use
  `jdk-openjdk` (rolling): its directory is renamed on each bump and silently breaks the path.
  Only LTS is pinnable.
- `dot_local/scripts/executable_minecraft-backup` — daily tarball of every instance's world tree
  to `/mnt/x9pro/minecraft-backups`, keeping the newest 3 per instance. Pauses+flushes saves via
  the server's tmux console when it's running so the snapshot is consistent. An instance with no
  `world*` dirs yet is skipped, not an error, and one instance's failure doesn't stop the rest.
  Run by `minecraft-backup.timer`.
- `dot_local/scripts/executable_gaming-mode` — `gaming-mode {on|off|status}` stops the whole
  self-hosted stack to free CPU/GPU/RAM for gaming, then restores exactly what was running.
  **Its `CANDIDATES` list must include every resource-heavy service** — add new services here.
- `dot_local/scripts/executable_check-live` — `just check-live`: what the repo declares vs what is
  running. Boot-readiness for a quadlet unit is a symlink in
  `$XDG_RUNTIME_DIR/systemd/generator/default.target.wants/`, **not** `is-enabled`, which reports
  `generated` for every generated unit. A container is matched to its quadlet through podman's
  `PODMAN_SYSTEMD_UNIT` label, since `navidrome` and `slskd` set `ContainerName=` while the rest
  carry a `systemd-` prefix. `cloudflare-ddns`, `immich-ml` and
  `immich-server` set `SuccessExitStatus=143`: their images do not trap SIGTERM, so podman
  reports 143 and systemd would otherwise mark them failed every time gaming mode stops
  them. Every section still consults gaming-mode's state file, which is what separates
  "intentionally stopped" from drift.
- **Both sunshine configs are `modify_` scripts** — the web UI rewrites `sunshine.conf` and
  `apps.json` whole on every Save, so a plain template would revert it and stay permanently dirty.
  `modify_sunshine.conf.tmpl` owns one line; `modify_apps.json.tmpl` owns the apps named in
  `OWNED`, deletes those in `RETIRED`, and passes through anything added in the UI. It matches
  sunshine's own writer (nlohmann `dump(4)`: 4 spaces, sorted keys, no trailing newline) so a UI
  save leaves `chezmoi diff` quiet, and it preserves each app's `uuid` — that is how a client
  remembers an app.
- **Sunshine captures the physical connector** (`Screencasting with KMS`), so the stream's
  resolution *is* the display's. `dot_local/scripts/executable_sunshine-client-mode` is the
  prep-cmd behind the "Desktop (client resolution)" app: it reads `SUNSHINE_CLIENT_WIDTH`/
  `_HEIGHT`/`_FPS` and switches the output to a matching mode, then restores it. Only a mode the
  display already advertises is used, and it always exits 0 — a non-zero prep-cmd aborts the
  stream. Sunshine's own `dd_*` auto-resolution options are Windows/macOS only.
- A prep-cmd runs **without a shell**, so `apps.json` needs absolute paths — no `~`, no `$HOME`,
  and no systemd `%h`. The path is rendered from the host's `user`.
- **DNS filtering is blocky**, a quadlet publishing only on loopback. CoreDNS
  forwards `.` to it with `policy sequential`, keeping Cloudflare as a second
  upstream, so a dead filter is unfiltered resolution rather than none.
  `policy sequential` is load-bearing: forward's default is `random`, which
  would route half of all queries around the filter. The Corefile emits the hop
  only where the `blocky` quadlet is claimed, so claiming it is the single fact
  that turns filtering on. Lists refresh themselves every 24h; the `blocky`
  script drives the API and the dashboard buttons call it. `hosts` blocks keep
  their `fallthrough` and run first, so no internal name reaches the filter.
- **Neither OliveTin nor blocky reloads a changed config**, so each has a `run_onchange` restart
  script (90, 95). OliveTin is the worse of the two: its watcher *appends* the changed file as an
  extra config source instead of replacing it, so after chezmoi's atomic rename every action and
  dashboard exists twice — duplicate titles leave one copy unreachable, fieldsets interleave under
  the wrong headings, and the built-in Actions view returns. blocky simply reads its config once at
  start, so a new blocklist URL needs the restart; `/lists/refresh` only re-downloads lists it
  already knows.
- **The dashboard is OliveTin**, a systemd *user* unit rather than a container —
  `gaming-mode` drives `systemctl --user` and the container buttons call
  `podman` directly. Its whole config is generated: tiles come from `endpoints`,
  and presentation, logins and buttons from `.chezmoidata/dashboard.yaml`.
  Adding a button is a data edit. **OliveTin's own `{{ }}` placeholders must be
  written as `{{ "{{ x }}" }}` in the template**, or chezmoi evaluates them.
  Deliberately absent from `units`: gaming mode stops that list, and this is
  what turns it back off. Also absent from `check-live`'s declared/failed-units
  sweep, so only the `dash` endpoint probe covers it. Keep `olivetin-bin`
  current: CVE-2026-28790 covers unauthenticated action termination in exactly
  this guests-must-log-in configuration.

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
(`turisa`/`arthur`), and `simulate-host` would render the previewing machine's home.

Each host also carries `syncthing_id`, its device ID.

## Two-phase bootstrap

A device ID is derived from a TLS cert Syncthing generates on first run, so it cannot be known in
advance:

1. `chezmoi apply` — installs syncthing (answer `y` at the install prompt; see "Packages" above),
   enables the user unit, and writes a config with **no** folders or devices (an empty
   `syncthing_id` omits them rather than emitting half a config).
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
  version, and expands every default into ~200 lines. A static template loses all of that on every
  apply and Syncthing puts it straight back, so the file stays permanently dirty.
  `modify_config.xml.tmpl` gets the current file on **stdin** and owns only the `<folder>` and
  top-level `<device>` elements plus a few `<options>`; everything else passes through.
  **The transform must be idempotent** — chezmoi diffs our stdout against the file on disk, so
  re-running on our own output has to be byte-identical. Verify with two passes:

  ```
  tools/simulate-host mars execute-template < dot_local/state/private_syncthing/modify_config.xml.tmpl > /tmp/m.py
  ssh mars.arthurjordao.dev cat .local/state/syncthing/config.xml > /tmp/live.xml
  python3 /tmp/m.py < /tmp/live.xml > /tmp/1.xml && python3 /tmp/m.py < /tmp/1.xml > /tmp/2.xml && diff /tmp/1.xml /tmp/2.xml
  ```
- Go templates render booleans as `true`/`false`; Python needs `True`/`False`. Use
  `ternary "True" "False"` when generating Python from chezmoi data.
- **`~/Emulation/saves/` is a farm of absolute symlinks**, not save data. EmuDeck points each one
  at wherever that emulator actually stores saves. Syncing it would replicate broken links (wrong
  username on the far side) and zero bytes. Every folder path must be **real storage on both
  hosts**.
- **`~/Emulation/roms/` is not pure content.** EmuDeck installs emulators inside it — Cemu in
  `wiiu/`, the Sega Model 2 emulator in `model2/`, launcher scripts in `emulators/`. Those are
  per-host and are excluded by `Emulation/roms/.stignore`. Write structural rules there, not a list
  of files you noticed. `just emu-sync-check` reports what is uncovered.
- **XML comments cannot contain `--`**, so the config template cannot write a `--flag` in a
  comment. Syncthing rejects the whole file.
- **`emu-save-dolphin`'s folder root is Dolphin's whole flatpak data dir**, so its `.stignore`
  admits only `GC/`, `Wii/` and `StateSaves/`. Each needs *two* lines (`!/GC` and `!/GC/**`):
  without the second, children fall through to the catch-all and only an empty directory syncs.
- **Switch saves are per-profile, and the profile registry is one binary file.** Saves live at
  `nand/user/save/0000000000000000/<profile-uuid>/`; the registry is
  `nand/system/save/8000000000000010/su/avators/profiles.dat`. Sync the saves without it and Eden
  reports "a save with no attached profile", because each host's Eden generated its own profile
  UUID. `emu-switch-profiles` is **oneway from mars** on purpose: an opaque binary cannot be
  merged, so two-way would be last-writer-wins and would drop a host's profile.
- **`gamelist.xml` is the most conflict-prone file here.** ES-DE rewrites it on exit to update
  `playcount`/`playtime`/`lastplayed`, so playing on both hosts between syncs conflicts every
  session. Low stakes, and it is also what carries favourites and the per-game emulator choice.
- ES-DE gamelists are **not valid XML** — two root elements (`<alternativeEmulator>` then
  `<gameList>`), which strict parsers reject outright. Extract the `<gameList>` fragment.

## Changing the folder list

`run_onchange_after_80-restart-syncthing.sh.tmpl` restarts the unit. Its trigger hashes the **data**
as well as the template, since a `.chezmoidata/syncthing.yaml` edit changes the output while leaving
every template byte identical. This is the only script that still needs the trick — the config it
watches is a `modify_` script whose output depends on the live file on disk, so unlike the `/etc`
bodies it cannot be inlined here.

Inspect before applying:

```
tools/simulate-host mars execute-template < dot_local/state/private_syncthing/modify_config.xml.tmpl
tools/simulate-host mercury execute-template < dot_local/state/private_syncthing/modify_config.xml.tmpl
```

# Adding a new service (checklist)

1. `dot_config/containers/exact_systemd/<svc>.container` (+ `<svc>.env.tmpl` if it needs secrets;
   create a 1Password item titled for the service, put its fields **inside a section**, and
   add the title to `secrets.items`). Name it `.container.tmpl` if it publishes a proxied
   port, and write that port as

   ```
   PublishPort={{ template "endpoint-port" (dict "hosts" .hosts "endpoint" "<name>") }}:<image port>
   ```

   Same for `TZ` (`{{ .timezone }}`) and any path on the external SSD (`storage-path`) — see
   "Three concerns per service".
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
   (`calibre-web-automated` → `books`). That endpoint name is also what step 1 looks up.
3. Verify before applying: `just check` catches a missed list (step 2 is exactly what
   `check-consistency` cross-references). Then `./tools/simulate-host <host> managed | grep <svc>`
   for the quadlet and the three `execute-template` commands above to read the edge output.
4. **(Optional — public internet access)** `public: true` on the endpoint, then on mars run
   `cloudflared tunnel route dns <tunnel-id> <svc>.arthurjordao.dev` once to create the CNAME.
   Do NOT use the dashboard (see the exposure section above).
5. On mars: `chezmoi apply` (renders and deploys /etc, reloads caddy/coredns, restarts
   cloudflared), then `systemctl --user daemon-reload && systemctl --user start <svc>.service`.

# Working in this repo

- The user runs `chezmoi apply` themselves — don't run it for them.
- **Keep comments short.** State the constraint, not how it was discovered, what it looked like
  when broken, or what an earlier version got wrong. One or two lines is usually enough.
- **nvim is managed with `exact_` on every directory level** (`dot_config/exact_nvim/`).
  `exact_` does not recurse — a level without the prefix silently stops propagating deletes.
  `lazy-lock.json` and `lazyvim.json` are `symlink_` entries into `.nvim-state/`, which chezmoi
  ignores as source state, so nvim's writes land in git. Both symlinks bake an absolute path from
  `.chezmoi.sourceDir`: moving or re-cloning the repo dangles them until the next apply.
- Configs are cross-platform by default. Gate only what *costs* something — packages, units,
  `/etc` writes, secret reads, `run_once_*` scripts. An unused config on the wrong host is inert.
- The whole edge — Caddy, CoreDNS, cloudflared, `gaming-mode` — is generated from
  `.chezmoidata/`. Nothing about a service is declared in two places.
- Never re-create a static `dot_local/scripts/executable_gaming-mode`,
  `dot_config/systemd/user/minecraft@.service` or `private_dot_ssh/private_config`. The `.tmpl`
  files are the only source; a static sibling would be silently ignored and drift forever. Same
  for the four bodies in `.chezmoitemplates/etc/` — a sibling under `etc/` would deploy nowhere.
- On a fresh Linux host, `run_once_after_30-set-default-shell.sh` needs `fish` present. It's in
  the `common` group of `packages.arch`, but if the shell change is skipped on first apply (the
  install prompt declined, or packages not installed yet), just run `chezmoi apply` again.
