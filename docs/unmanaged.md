# What lives only on mars

Things mars depends on that `chezmoi apply` does not create. Rebuilding the box means
walking this list by hand. A second section at the end covers **phobos**, the RG353V
handheld, which has a short list of its own.

Everything here was read off the running host. Where a file is short, its whole body is
inlined so this document is enough on its own.

The generated files are **not** here: `/etc/caddy/Caddyfile`, `/etc/coredns/Corefile`,
`/etc/cloudflared/config.yml` and `/etc/caddy/caddy.env` are rendered from
`.chezmoidata/` and installed by `run_onchange_after_70-deploy-etc.sh.tmpl`. Never write
them by hand — the next apply overwrites them. Only the *units* that run those services
are unmanaged.

---

## A. Host state to recreate

### The caddy binary is hand-built

`/usr/bin/caddy` is owned by **no package**. `xcaddy-bin` ships only the builder; the
binary running in production was built with the Cloudflare DNS provider compiled in.
Without that module Caddy cannot answer the DNS-01 challenge and **every certificate
fails to issue**.

```sh
xcaddy build --with github.com/caddy-dns/cloudflare
sudo install -m755 ./caddy /usr/bin/caddy
```

Verify: `caddy list-modules | grep dns.providers.cloudflare` must print that line.
Currently running v2.11.2.

### The caddy user

`caddy.service` runs as `User=caddy`, and no package creates the account.

```sh
sudo useradd --system --home-dir /var/lib/caddy --shell /sbin/nologin caddy
```

`/var/lib/caddy` holds Caddy's ACME state, including issued certificates. Losing it
forces a re-issue of every certificate, which is subject to Let's Encrypt rate limits.

### Linger for turisa

Without this, **no user unit starts at boot** — the entire self-hosted stack stays down
until someone logs in.

```sh
sudo loginctl enable-linger turisa
```

### logind must not kill turisa's processes

CachyOS ships `/etc/systemd/logind.conf.d/steam-deckify.conf` with
`KillUserProcesses=True`, which kills processes spawned over SSH the moment the session
ends. The `zz-` prefix is what makes this drop-in win.

```ini
# /etc/systemd/logind.conf.d/zz-keep-turisa-processes.conf
[Login]
KillExcludeUsers=turisa
```

### Kernel cmdline: pcie_aspm=off

Fixes NVMe PCIe AER errors that dropped SSH connections. The bootloader is limine, and
this whole file is hand-maintained.

```sh
# /etc/default/limine
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=/@ root=UUID=28a7565f-3c81-4424-9351-17558c2b0736"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
KERNEL_CMDLINE[default]+=" pcie_aspm=off"
```

Verify after boot: `grep -o pcie_aspm=off /proc/cmdline`.

### The external SSD mount

Every media path, the immich library and the minecraft backups live here. `nofail` keeps
a missing disk from blocking boot.

```
# /etc/fstab
UUID=30CD-0AC4 /mnt/x9pro exfat defaults,nofail,uid=1000,gid=1000,umask=022,x-systemd.automount 0 0
```

### Name resolution: two halves of one fix

systemd-resolved sent private reverse lookups to mDNS and waited out the timeout — a PTR
for a LAN address cost a flat 7.7s. Turning resolved's mDNS off fixed that but removed
glibc's only route to `.local`, so both halves are needed together.

```sh
sudo nmcli connection modify ap-not-found connection.llmnr 0 connection.mdns 0
```

```
# /etc/nsswitch.conf — the hosts: line, with mdns_minimal right after mymachines
hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns
```

A copy of the original is at `/etc/nsswitch.conf.pre-mdns`. `avahi-daemon` provides
`.local` service discovery independently, which is why dropping resolved's mDNS is safe.

### System units

None of these are packaged. `coredns` and `cloudflared` binaries *are* package-owned —
only their units are missing.

```ini
# /etc/systemd/system/caddy.service
[Unit]
Description=Caddy Web Server
After=network-online.target
Wants=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
EnvironmentFile=/etc/caddy/caddy.env
TimeoutStopSec=5s
Restart=on-failure
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/coredns.service
[Unit]
Description=CoreDNS DNS Server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/coredns -conf /etc/coredns/Corefile
Restart=on-failure
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/cloudflared.service
[Unit]
Description=cloudflared
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=15
Type=notify
ExecStart=/usr/bin/cloudflared --no-autoupdate --config /etc/cloudflared/config.yml tunnel run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

```ini
# /etc/systemd/system/cloudflared-update.service
[Unit]
Description=Update cloudflared
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/bin/bash -c '/usr/bin/cloudflared update; code=$?; if [ $code -eq 11 ]; then systemctl restart cloudflared; exit 0; fi; exit $code'
```

```ini
# /etc/systemd/system/cloudflared-update.timer
[Unit]
Description=Update cloudflared

[Timer]
OnCalendar=daily

[Install]
WantedBy=timers.target
```

Enable with `sudo systemctl enable --now caddy coredns cloudflared cloudflared-update.timer`.

blocky needs nothing here: it is a quadlet, and it refreshes its own blocklists.

### Drop-ins

```ini
# /etc/systemd/system/cockpit.socket.d/override.conf — keep cockpit off the LAN
[Socket]
ListenStream=
ListenStream=127.0.0.1:9090
```

```ini
# /etc/systemd/system/tailscaled.service.d/before-umount.conf
[Unit]
Before=umount.target
```

### Firewall (ufw)

`ufw` is active on the iptables-nft backend; `nftables.service` is inactive. Nothing in the
repo touches the firewall, so every rule below is lost on a rebuild. Default policy is
deny incoming, allow outgoing.

```sh
sudo ufw allow 22                 # ssh (tcp+udp)
sudo ufw allow 9987/udp           # teamspeak3 voice
sudo ufw allow 10011/tcp          # teamspeak3 serverquery
sudo ufw allow 30033/tcp          # teamspeak3 filetransfer
sudo ufw allow 53/tcp             # coredns
sudo ufw allow 53/udp
sudo ufw allow 443/tcp            # caddy
sudo ufw allow 9090/tcp           # cockpit (inert: the socket binds 127.0.0.1 only)
sudo ufw allow 10400:10401/udp
sudo ufw allow from 192.168.15.0/24                              # LAN is blanket-accepted
sudo ufw allow from 192.168.15.0/24 to any port 27031            # steam remote play
```

**Minecraft is the only port reachable from the internet** (the router forwards 25565/tcp),
so it is the only one rate-limited. **Insert the exemptions first — order decides
everything.** iptables is first-match, and the blanket LAN accept sits *below* the
minecraft rule, so without these two the limit would apply to household players too:

```sh
sudo ufw insert 1 allow from 192.168.15.0/24 to any port 25565 proto tcp comment 'minecraft: LAN exempt from limit'
sudo ufw insert 2 allow from 100.64.0.0/10   to any port 25565 proto tcp comment 'minecraft: tailscale exempt'
sudo ufw limit 25565/tcp comment 'minecraft: rate-limit external joins'
```

`ufw limit` is `-m recent`: 6 new connections per source IP per 30s, then REJECT, with the
window refreshed on every hit. A Java client opens two connections per join (status ping,
then login), so external players get roughly three join attempts per 30 seconds. Verify the
exemptions land above the limit with `sudo ufw status numbered | grep 25565`, and watch it
with `journalctl -k -g 'UFW LIMIT BLOCK'`.

mars has no global IPv6 and no IPv6 egress, so the v6 duplicates of these rules are inert.

Possibly stale: the `alvr` application profile rules (`9943:9944` tcp+udp) remain, though the
`vr` role and its package were removed from the repo.

### Minecraft instance contents

The repo declares each instance and writes its `~/minecraft/<instance>/start`. Everything
else in that directory is hand-placed and not reconstructible from a clone: the server jar,
`eula.txt`, `server.properties`, worlds, plugins and datapacks.

`matcha` runs **Paper 26.2 build 112** (`paper-26.2-112.jar`, sha256 `bd3a58cf9687…`, from
`https://fill.papermc.io/v3/projects/paper/versions/26.2/builds`) with the **Matcha
Flavoured** datapack, [Modrinth `QI0EmgZ1`](https://modrinth.com/project/QI0EmgZ1), version
1.12:

```
world/datapacks/Matcha_Flavoured_1_12.zip   sha1 77d080d2fe207a886c8c784ac239dec54a213065
```

**The same zip is both the datapack and the resource pack** — the author ships them bound
together (one `pack.mcmeta` over both `data/` and `assets/`), so the file in
`world/datapacks/` is also the one served to clients. These lines in `server.properties`
serve it:

```properties
resource-pack=https://cdn.modrinth.com/data/QI0EmgZ1/versions/E9rngRfK/Matcha_Flavoured_1_12.zip
resource-pack-sha1=77d080d2fe207a886c8c784ac239dec54a213065
require-resource-pack=true
resource-pack-prompt={"text":"Matcha Flavoured needs its textures - item names and recipes depend on them."}
```

Required, not optional: the pack carries item names and recipe icons, so declining leaves
the game unreadable rather than merely untextured.

**`resource-pack-prompt` is parsed as a JSON text component, not a plain string.** Plain
text logs `Failed to parse resource pack prompt` at every boot and the prompt is dropped —
the server still starts, so it is easy to miss.

Updating the pack means replacing the zip **and** both `resource-pack*` lines with the new
version's URL and sha1 — a stale sha1 makes every client reject the download. Install the
datapack before the world is first generated; Matcha shuffles item progression, and it warns
against adding it to an existing world.

`difficulty` selects the pack's own mode: `easy` is its relaxed variant, `normal` the
intended challenge. `matcha` is on `normal`. Confirm the pack is live with
`minecraft attach` then `datapack list` — it should report
`[file/Matcha_Flavoured_1_12.zip (world)]` among the enabled packs.

**A fresh `server.properties` is `white-list=false`, and 25565 is the one internet-facing
port-forward.** Any new instance therefore needs `white-list=true` and a `whitelist.json`
copied from the instance it replaces, or switching to it publishes an open server. Both
`vanilla` and `matcha` carry the same three-player whitelist.

Matcha logs its own upstream defects on every boot — stray `HELP.txt` files under
`dimension_type/`, `jukebox_song/` and `advancement/`, plus two unparseable advancement
files. They are the pack author's, harmless, and not worth chasing.

### RCON is disabled on purpose

`enable-rcon=false` in each instance's `server.properties` (not managed by this repo). It
used to listen on `*:25575` on `vanilla`, and the LAN is blanket-accepted, so anything on the
network could reach it. Nothing needs it — `minecraft-backup` drives the console through the
server's tmux session, not RCON.

Do not "fix" this by binding it to loopback: vanilla and Paper have no `rcon.ip`, so RCON
inherits `server-ip`, and setting that would bind the *game* port to loopback too. Leave it
off.

`rcon.password` and `rcon.port` were deleted from the file as well, but **the server rewrites
`server.properties` on every start** and re-adds the full key set, so both reappear with
defaults — an *empty* password and 25575. That is fine and expected: `enable-rcon=false` is an
explicit value and survives, which is what keeps the port closed. Deleting the lines is not a
control, it just kept the old password off disk.

### No longer load-bearing

- **`archlinux-java` default.** The atm10-tts modpack launcher used to fall through to
  bare `java`, making the system-wide default silently load-bearing. Each instance's JVM
  is now pinned in `.chezmoidata/minecraft.yaml` and injected by its managed
  `~/minecraft/<instance>/start` script. Recorded so nobody hunts for a dependency that
  was removed.
- **`~/cloudflare-ddns/`.** Was an untracked clone of the abandoned Python
  cloudflare-ddns, complete with a venv and an uncommitted local patch. Replaced by the
  `cloudflare-ddns` quadlet on upstream's v2 image. Delete the directory if it is still
  present.

### Known drift

Rolling **`jdk-openjdk`** (26) is installed but declared nowhere. It renames its own
directory on every bump, so no pinned path should ever point at it. Either
`paru -Rns jdk-openjdk` or declare it deliberately in `packages.arch.minecraft`.
`tools/check-consistency` reads repo data only and cannot see this — it needs a check
against the live host.

---

## B. Secrets and external services

- **1Password vault `dotfiles`** is the root of every secret the repo renders. Item
  titles are declared in `.chezmoidata/secrets.yaml`; field names are not — templates
  read them off the item. Lose the vault and no apply can complete. Note that
  `onepasswordItemFields` silently drops any field that is not inside a **section**.
- **Cloudflare Tunnel credentials** at `~/.cloudflared/<tunnel_id>.json`, where
  `tunnel_id` is in `.chezmoidata/cloudflare.yaml`. Correctly absent from the repo.
  Recreate with `cloudflared tunnel login` then `cloudflared tunnel create <name>`, which
  mints a **new** ID that must be written back into that data file.
- **The tunnel is locally managed.** Never add a Public Hostname in the Cloudflare
  dashboard: that attaches a *remote* config which cloudflared obeys while silently
  ignoring `config.yml`, and there is no supported way to detach it. Routes are created
  once per hostname with `cloudflared tunnel route dns <tunnel-id> <hostname>`.
- **Cloudflare API tokens.** Two distinct ones, both needing *Edit DNS* on the zone: one
  for Caddy's DNS-01 challenge (`/etc/caddy/caddy.env`, from the `caddy` item) and one
  for the DDNS container (from the `cloudflare-ddns` item).
- **The `memory` bearer token** is a `MEMORY_BEARER_TOKEN` field on the `caddy` item, and the
  **same string** is configured by hand in two more places: the Request headers section of the
  custom connector on claude.ai, and `claude mcp add --header` on each host that uses it.
  Rotating it means editing all three.
- **The claude.ai custom connector** at `https://memory.arthurjordao.dev/mcp`, added under
  Customize → Connectors with `Authorization` = `Bearer <token>` as a request header. Header
  auth is a beta feature on that account; if it ever disappears from the dialog the endpoint is
  unauthenticated and must come out of the tunnel.
- **Router port-forward.** TCP 25565 → mars, for Minecraft. The only forwarded port.
  `minecraft.arthurjordao.dev`'s A record is kept current by the `cloudflare-ddns`
  quadlet.
- **Wi-Fi PSK** lives in the NetworkManager profile `ap-not-found` under
  `/etc/NetworkManager/system-connections/`, root-only and not in the repo. There is also
  a wired profile, "Conexão cabeada 1".

---

## C. Data, not config

None of this is reconstructible from the repo.

| What | Where | Backup |
|---|---|---|
| immich library | `/mnt/x9pro` | none |
| media (music, books, book-ingest) | `/mnt/x9pro` | none |
| minecraft worlds, mods, plugins | `~/minecraft/<instance>/` | world trees only, below |
| minecraft backups | `/mnt/x9pro/minecraft-backups` | newest 3 tarballs per instance |
| notes and memory store | `/mnt/x9pro/memory/` | none |
| podman named volumes | `~/.local/share/containers` | none |
| syncthing identity | `~/.local/state/syncthing/{cert,key}.pem` | none — regenerating changes the device ID |
| syncthing database | `~/.local/state/syncthing/` (SQLite) | none, rebuildable by rescanning |

`minecraft-backup.timer` runs daily and keeps the newest 3 tarballs of every instance's
world tree. Only worlds: the server jar, plugins, mods and `server.properties` are not
backed up. **Nothing here has an offsite copy**, and the external SSD is a single exfat
volume with no redundancy.

The syncthing device ID is derived from `cert.pem`. Regenerating it means editing
`syncthing_id` in `.chezmoidata/hosts.yaml` and re-approving the device on every peer.

---

## D. Deliberately disposable

Left over from diagnosing Wi-Fi drops. Do **not** recreate these; they are listed only so
a future reader does not mistake them for load-bearing.

- `/etc/systemd/system/wifi-linklog.service`
- `/usr/local/bin/wifi-linklog`

---

# What lives only on phobos

The Anbernic RG353V handheld, running dArkOS (Debian 13 trixie, arm64, user `ark`).
None of this survives reflashing the OS card.

Root is btrfs with roughly 4 GB free, so keep the installed footprint small.

### Hostname

The image ships as `rg353v`. chezmoi requires the hostname to match the key in
`.chezmoidata/hosts.yaml` exactly — a mismatch fails every template with
`map has no entry for key "rg353v"`.

```sh
sudo hostnamectl set-hostname phobos
sudo sed -i 's/\brg353v\b/phobos/g' /etc/hosts
```

### chezmoi

Not in Debian's archive. Fetch the arm64 package from
https://github.com/twpayne/chezmoi/releases:

```sh
curl -fsSLO https://github.com/twpayne/chezmoi/releases/download/v2.72.0/chezmoi_2.72.0_linux_arm64.deb
sudo dpkg -i chezmoi_2.72.0_linux_arm64.deb
```

### Remote Services

ArkOS leaves sshd off, and the Options-menu toggle is per-boot. SSH access is **not**
persistent — re-enable it from the handheld after every reboot. This is a deliberate
ArkOS default, not a fault.

### Tailscale

The apt repo is added by `chezmoi apply`, but joining the tailnet is interactive and
prints a URL to open in a browser:

```sh
sudo tailscale up
```

The address it assigns goes into `ip.tailscale` in `.chezmoidata/hosts.yaml`. Declare
both `lan` and `tailscale` in the same edit: the Corefile's host blocks test for the
`ip` key rather than its values, so a half-declared `ip` emits a hosts line with no
address into the config mars serves for the whole fleet.

### dArkOS updates

Options → Update may revert `/etc`, the hostname included. Re-check this list after any
OS update.
