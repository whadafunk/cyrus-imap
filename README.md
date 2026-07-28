# Mail stack

A collection of components for a self-hosted mail setup, orchestrated by the
single `docker-compose.yml` at this repo's root. Each component keeps its own
source/config/data in its own subdirectory, but `docker compose` commands are
run from here, not from inside a component's folder.

## Components

- **[cyrus-imap/](cyrus-imap/)** — Cyrus IMAP + SASL container, authenticating
  via `saslauthd`. See `cyrus-imap/README.md` for setup.
- **roundcube/** — webmail frontend (official `roundcube/roundcubemail`
  image) for the Cyrus backend above. MVP: IMAP login/browsing only —
  sending mail (needs an SMTP submission service, not set up yet) and Sieve
  filter management are deliberately out of scope for now.

## Quick start

```sh
cp cyrus-imap/config/imapd.conf.example cyrus-imap/config/imapd.conf
cp cyrus-imap/config/cyrus.conf.example cyrus-imap/config/cyrus.conf
docker compose up -d --build
```

Roundcube comes up alongside Cyrus automatically (same `docker-compose.yml`)
at `http://<host>:8090` — log in with any Cyrus user (e.g. the `admin`/
`daniel` test accounts baked into the `cyrus-imap` image for now).
