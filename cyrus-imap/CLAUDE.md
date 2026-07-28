# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Debian-based Docker image for Cyrus IMAP, authenticating users via SASL
(`PLAIN`/`LOGIN`) through `saslauthd` configured to bind against an
**external** LDAP server (no LDAP server is bundled — config always points
outward). This is infrastructure/config, not application code: there's no
build step, test suite, or language runtime — the "code" is the Dockerfile,
plain static config files, and a shell entrypoint.

Config is deliberately plain right now, not templated: `config/imapd.conf`,
`config/cyrus.conf`, and `config/saslauthd.conf` are real, gitignored files
bind-mounted into the container as-is (edit + restart, no rebuild, no env-var
substitution, no staging/copy step). Only `.example` versions are checked in.
This was a conscious simplification away from an earlier `envsubst`-templated
design — if it's revisited, expect the `.tmpl` + entrypoint-rendering
approach to come back.

Auth backend is currently `saslauthd -a shadow` (plain Unix accounts via
`useradd`/`chpasswd` in the running container), not LDAP — `saslauthd.conf`
is present for reference/future LDAP use but isn't read by anything right
now. The user has expressed wanting to keep multiple SASL config variants
(saslauthd with different backends, and Cyrus's own `auxprop` mechanism) on
hand to switch between later — nothing is built for that yet, don't assume
any particular variant-switching mechanism without asking.

## Commands

Run from the repo root — `docker-compose.yml` lives there, not in this
`cyrus-imap/` folder, so every component in the repo can be run independently
from one place.

```sh
cp cyrus-imap/config/imapd.conf.example cyrus-imap/config/imapd.conf
cp cyrus-imap/config/cyrus.conf.example cyrus-imap/config/cyrus.conf
docker compose up -d --build  # build image and start the container
docker compose logs -f        # follow entrypoint / cyrus master output
docker compose down           # stop (add -v to also drop the named volumes)

# create a shadow user to log in as (shadow auth, no LDAP right now)
docker exec <container> useradd -M <name>
echo "<name>:<password>" | docker exec -i <container> chpasswd
```

There is no automated test suite. To verify a change manually, exec into the
running container and use the Cyrus test clients directly (not on `$PATH`,
under `/usr/lib/cyrus/bin/`):

```sh
docker exec <container> testsaslauthd -u <user> -p <password>          # isolates the LDAP/SASL leg
docker exec <container> /usr/lib/cyrus/bin/imtest -t '' -u <user> -a <user> -w <password> -p 143 -m PLAIN localhost   # STARTTLS login
docker exec <container> /usr/lib/cyrus/bin/imtest -s -u <user> -a <user> -w <password> -p 993 -m PLAIN localhost      # implicit-TLS login
```

`imtest -p 143` requires `-t ''` (STARTTLS); `imtest -p 993` requires `-s`
(implicit TLS) instead — using the wrong flag for the port makes it hang
rather than error, since it waits for a TLS handshake that never starts.

## Architecture

- **`Dockerfile`** — installs `cyrus-imapd`, `sasl2-bin`, `libsasl2-modules-ldap`
  on `debian:bookworm-slim`; no compilation, just apt packages. No longer
  `COPY`s any config in — `cyrus.conf`/`imapd.conf` are bind-mounted at
  runtime instead (see below), so config edits don't require a rebuild.
- **`config/imapd.conf.example`** / **`config/cyrus.conf.example`** /
  **`config/saslauthd.conf.example`** — checked-in templates to copy to
  `config/imapd.conf` / `config/cyrus.conf` / `config/saslauthd.conf` and edit
  directly with real values. The real files are gitignored — `saslauthd.conf`
  because it can hold `ldap_bind_pw` in cleartext, `imapd.conf`/`cyrus.conf`
  because they're meant to carry a given deployment's own customizations
  rather than the checked-in defaults — and bind-mounted directly by
  `docker-compose.yml` into the container (`imapd.conf` → `/etc/imapd.conf`,
  `cyrus.conf` → `/etc/cyrus.conf`), no staging/copy step, no rewritten
  permissions. `cyrus.conf.example` mirrors the user's own current setup —
  `imap`/`imaps`/`lmtpunix`, plus a network-facing `lmtp` service
  (`listen="0.0.0.0:lmtp"`, unauthenticated via `-a` — a deliberate but
  security-relevant choice, not an oversight), `sieve` (localhost), `notify`,
  and `idled`. POP3/NNTP/HTTP are still stripped from the Debian default.
- **`entrypoint.sh`** — the only "logic" in this repo. In order: checks
  `imapd.conf`/`cyrus.conf` are actually mounted, generates a self-signed TLS
  cert on first boot only (persisted in the `cyrus_tls` volume, reused on
  restart), recreates the `/run/cyrus/*` runtime dirs (tmpfs, doesn't survive
  restarts), runs `cyrus makedirs --cleansquat` to initialize `/var/lib/cyrus`
  if the volume is empty, starts `saslauthd -a shadow` in the background,
  waits for its Unix socket, then `exec`s `/usr/sbin/cyrmaster` (not `master`
  — that's the binary name on other distros) in the foreground as PID 1.
- **`docker-compose.yml`** / **`.env.example`** — wiring for the above. The
  only remaining env var is `TLS_CN` (self-signed cert subject); everything
  else lives entirely in the bind-mounted plain config files now.

## Known quirks (verified by hands-on testing against a throwaway OpenLDAP)

- Even though `autocreate_quota: 0` in `imapd.conf` is documented as
  "disabled", a freshly LDAP-authenticated user still gets their `INBOX`
  auto-created on first `SELECT` — no separate mailbox-provisioning step is
  needed. If a user can authenticate but `SELECT INBOX` fails, that's a
  regression worth investigating, not expected behavior.
- `allowplaintext: no` is intentional: LDAP simple-bind auth needs the
  cleartext password, so `PLAIN`/`LOGIN` must never be usable before a TLS
  layer (STARTTLS or implicit TLS) is established.
- The Debian `cyrus-sasl2-doc` package does not ship the `LDAP_SASLAUTHD`
  reference doc on bookworm; the LDAP config keys used in
  `saslauthd.conf` were confirmed via
  `strings /usr/sbin/saslauthd | grep '^ldap_'`.
