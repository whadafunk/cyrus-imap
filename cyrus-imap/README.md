# Cyrus IMAP + SASL (LDAP) container

Debian-based Cyrus IMAP server that authenticates via SASL `PLAIN`/`LOGIN`,
verified by `saslauthd` against an external LDAP server.

## Quick start

Run from the repo root (`docker-compose.yml` lives there, not in this folder):

```sh
cp cyrus-imap/config/imapd.conf.example cyrus-imap/config/imapd.conf
cp cyrus-imap/config/cyrus.conf.example cyrus-imap/config/cyrus.conf
cp cyrus-imap/config/saslauthd.conf.example cyrus-imap/config/saslauthd.conf
# edit cyrus-imap/config/saslauthd.conf with your LDAP server details
# (optionally) cp .env.example .env and set TLS_CN
docker compose up -d --build
```

Ports:
- `143` - IMAP with STARTTLS
- `993` - IMAPS (implicit TLS)

Plaintext auth is rejected unless TLS is already in place (`allowplaintext: no`),
so clients must either connect on 993 or issue STARTTLS on 143 before logging in.

## Configuration (`config/imapd.conf`, `config/cyrus.conf`, `config/saslauthd.conf`)

These are plain Cyrus/saslauthd config files, bind-mounted into the container
by `docker-compose.yml` - no templating or env-var substitution happens at
container start. Edit them directly and restart the container to pick up
changes (no rebuild needed). All three are gitignored - `saslauthd.conf` holds
`ldap_bind_pw` in cleartext, and `imapd.conf`/`cyrus.conf` are meant to carry
your own deployment's customizations rather than the checked-in defaults -
only the `.example` versions are checked in.

Key fields to fill in in `config/saslauthd.conf`:

| Key | Purpose |
|---|---|
| `ldap_servers` | e.g. `ldap://ldap.example.com` or `ldaps://...` |
| `ldap_search_base` | Base DN to search for user entries |
| `ldap_filter` | Search filter, `%u` is replaced with the login name |
| `ldap_bind_dn` / `ldap_bind_pw` | Service account used to search LDAP before verifying the user's own bind |
| `ldap_scope` | `base`, `one`, or `sub` |
| `ldap_start_tls` | `yes` to upgrade a plain `ldap://` connection with STARTTLS |
| `ldap_tls_check_peer` | `yes`/`no`, whether to validate the LDAP server's cert |
| `ldap_tls_cacert_file` | Path (inside the container) to a CA bundle, if needed (commented out by default) |

In `config/imapd.conf`, the only field you're likely to change is `admins`
(space-separated Cyrus admin usernames).

`TLS_CN` (CN for the auto-generated self-signed cert, default `localhost`)
is still an env var - see `.env.example` - since it's a cert-generation
parameter rather than a Cyrus/saslauthd config value.

## TLS certificate

On first boot, if no cert is found at `/etc/cyrus/tls/{server.crt,server.key}`,
the container generates a self-signed one and persists it in the `cyrus_tls`
volume, so it survives restarts.

To use a real certificate instead, bind-mount it over that path, e.g. in
`docker-compose.yml`:

```yaml
volumes:
  - ./certs:/etc/cyrus/tls   # must contain server.crt and server.key
```

## Notes

- New LDAP users get a working `INBOX` automatically on first login - no
  separate provisioning step needed.
- Only IMAP/IMAPS + LMTP delivery + local Sieve are enabled (`config/cyrus.conf`);
  POP3/NNTP/HTTP are left out since only IMAP was requested. Add services there
  if you need them.
- Mailbox data lives in the `cyrus_data`/`cyrus_spool` volumes - back those up.
- `admins` users (in `imapd.conf`) must also exist in LDAP to actually log in
  as admin (Cyrus authorization is separate from SASL authentication).
