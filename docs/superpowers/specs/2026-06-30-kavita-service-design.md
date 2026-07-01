# Kavita reading server — design

Add Kavita (self-hosted comics/manga/ebook reader) to the mars homelab, following the
existing container + Caddy + CoreDNS conventions.

## Container

`dot_config/containers/systemd/kavita.container` — root-level quadlet (no shared network).

- Image `docker.io/jvmilazz0/kavita:latest`, `AutoUpdate=registry` (Kavita only publishes
  `:latest` / `:nightly`).
- Publishes `5000:5000` (Kavita's internal HTTP port).
- Runs as container-root, which maps to host user `turisa` under rootless podman — same as
  the music stack. No PUID/PGID (this image doesn't use that scheme) and no env-file /
  Bitwarden secrets (Kavita generates its own token key into the config volume).
- Volumes:
  - `kavita-config:/kavita/config` — named volume for state/metadata/covers.
  - `/mnt/x9pro/books:/books:ro` — single library root, read-only (Kavita only reads media).
    Sub-libraries (Manga/Comics/Books) are configured inside the Kavita UI under `/books`.

## Caddy

Appended to `etc/caddy/Caddyfile`: `kavita.arthurjordao.dev` → `localhost:5000`, Cloudflare
DNS-challenge TLS, JSON access log — identical shape to the other service blocks.

## DNS

`kavita.arthurjordao.dev` added to both the `(local_hosts)` (`192.168.15.23`) and
`(tailscale_hosts)` (`100.127.50.55`) blocks in `etc/coredns/Corefile` for split-horizon
resolution.

## Deploy (run by user on mars)

1. `mkdir -p /mnt/x9pro/books` if it doesn't exist.
2. `chezmoi apply` — deploys Caddyfile + Corefile to `/etc` and reloads those services.
3. `systemctl --user daemon-reload && systemctl --user enable --now kavita.service`.
4. Open `https://kavita.arthurjordao.dev`, create the admin account, add a library at `/books`.
