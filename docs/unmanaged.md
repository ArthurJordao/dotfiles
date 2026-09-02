# Bootstrapping pluto

**Every other host's unmanaged state lives in the notes store**, under `dotfiles/hosts/<host>` —
what the box is, what `chezmoi apply` does not create, and which of that could be automated and
has not been. Query the `memory` MCP.

pluto is the exception, and this file exists only for it: **pluto serves the notes store**, so
rebuilding pluto is the one case the store cannot answer. What follows is the floor — enough to
get the box back and reach everything else.

If the store ever moves to another host, this file's subject moves with it.

---

## Order matters

Hostname and tailscale both have to precede `chezmoi init`.

### 1. Hostname, before anything

Armbian ships as `orangepizero3`. chezmoi bakes `.hostname` into its generated config at `init`
time, and `.chezmoiignore` looks the name up under `missingkey=error` — a mismatch fails *every*
chezmoi command with `map has no entry for key`.

```sh
sudo hostnamectl set-hostname pluto
sudo sed -i 's/\borangepizero3\b/pluto/g' /etc/hosts
```

`hostnamectl` does not touch `/etc/hosts`, and once systemd-resolved's stub is disabled every
`sudo` prints `unable to resolve host pluto: System error`.

### 2. Tailscale, and the resolv.conf it breaks

```sh
sudo tailscale up                                              # interactive, prints a URL
sudo tailscale set --accept-dns=false
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

Personal tailnet, not the work one.

**All three lines are needed.** Debian/Armbian does not make `/etc/resolv.conf` a symlink to the
systemd stub the way Arch does, so Tailscale takes the file over directly, its capture of the
pre-existing upstreams comes up empty, and its `100.100.100.100` stub SERVFAILs everything
non-tailnet. That breaks pluto's *own* outbound resolution — cloudflared crash-loops, LAN clients
are unaffected — and neither `tailscale down/up` nor a `tailscaled` restart self-heals it.
`--accept-dns=false` stops Tailscale re-taking the file; the symlink actually restores it.

`chezmoi apply` re-asserts the last two lines on every run. They stay here because `tailscale up`
precedes the first apply.

### 3. chezmoi

Not in Debian's archive.

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
chezmoi init --apply https://github.com/ArthurJordao/dotfiles.git
```

The apply needs 1Password, which the `hooks.read-source-state.pre` hook installs on its own.

---

## Storage: root on the SSD, /boot on the card

Created by `sudo armbian-install`, option "Boot from SD, system on SATA/USB".

```
UUID=<ssd>              /                  ext4  defaults,noatime,commit=120,errors=remount-ro,x-gvfs-hide  0 1
UUID=<card>             /media/boot-media  ext4  defaults,nofail                                            0 2
/media/boot-media/boot  /boot              none  bind,nofail                                                0 0
```

**This board has no separate boot partition** — u-boot loads the kernel from a `/boot` directory
inside an ext4 filesystem, and the bind mount is what keeps kernel upgrades landing where u-boot
reads them.

**Never move `/boot` onto the SSD while still booting from the card.** apt writes the SSD copy,
u-boot keeps loading the card's, and every upgrade silently runs an old kernel. Backups of the
correct arrangement: `/etc/fstab.pre-spi` and `/etc/fstab.card-boot`.

`f3probe --destructive` every new microSD before flashing it. A counterfeit passes flash, boot and
checksum, and fails only when something writes past the real end.

---

## Caddy is built, not fetched, and not during an apply

coredns, OliveTin and xcaddy are pinned in `.chezmoidata/binaries.yaml` and installed by
`run_onchange_after_10-install-packages.sh.tmpl`. Caddy is compiled here from the same pin against
the `golang-1.27-go` toolchain declared in `packages.yaml`, which `check-consistency` C22 keeps in
step.

The release binaries carry no Cloudflare DNS provider. Without it Caddy cannot answer the DNS-01
challenge and **every certificate fails to issue**.

The build takes about seven minutes, so `chezmoi apply` only *reports* that caddy is behind its
pin. Run it yourself after a version bump:

```sh
just binaries-build
caddy list-modules | grep dns.providers.cloudflare
```

That grep must print the module. Debian's versioned Go packages install under
`/usr/lib/go-1.27/bin` and provide no `/usr/bin/go`; the build puts it on `PATH` itself.

`binaries-check` reports pinned vs installed vs upstream — daily via `binaries-check.timer`, on
the dashboard's Server fieldset, and as `just check-binaries`.

---

## The rest

- **Both DHCP reservations on the router** — `.32` for `end0`, `.31` for `wlan0`. Not static
  config on pluto and not in this repo; the H618 derives `end0`'s MAC from the SoC ID, so a
  rebuild that changes neither MAC keeps the addresses.
- **`/etc/coredns/{cert,key}.pem`** are self-signed, `CN=localhost`, valid to 2036, and exist only
  to satisfy the DoT listener — which is why the `dns` endpoint carries `tls_insecure`. Script 70
  generates them on a fresh edge host, so this is provenance, not a step.
- **No NetworkManager on this image** — netplan + systemd-networkd + wpasupplicant. `nmcli` does
  not exist; use `networkctl`.

Credentials that no rebuild can regenerate — the 1Password vault, the tunnel `.json`, the
Cloudflare API tokens, the `memory` bearer — are inventoried in the store under
`dotfiles/reference/secrets and credentials`.
