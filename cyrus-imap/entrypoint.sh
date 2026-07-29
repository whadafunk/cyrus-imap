#!/bin/bash
set -euo pipefail

# imapd.conf and cyrus.conf are plain, static files bind-mounted in by
# docker-compose (see docker-compose.yml) - no rendering needed. saslauthd.conf
# is mounted read-only at a staging path and copied here so we can lock down
# its permissions (it holds ldap_bind_pw in cleartext) without mutating the
# host-mounted source file.
[ -f /etc/imapd.conf ] || { echo "/etc/imapd.conf not found - mount config/imapd.conf there" >&2; exit 1; }
[ -f /etc/cyrus.conf ] || { echo "/etc/cyrus.conf not found - mount config/cyrus.conf there" >&2; exit 1; }
[ -f /etc/saslauthd.conf.src ] || { echo "/etc/saslauthd.conf.src not found - mount config/saslauthd.conf there" >&2; exit 1; }

cp /etc/saslauthd.conf.src /etc/saslauthd.conf
chown root:sasl /etc/saslauthd.conf
chmod 640 /etc/saslauthd.conf

# TLS certificate: use a mounted one if present, otherwise generate a
# self-signed cert on first run and keep reusing it from the volume.
CERT_DIR=/etc/cyrus/tls
mkdir -p "$CERT_DIR"
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
	echo "No TLS certificate found in $CERT_DIR, generating a self-signed one for CN=${TLS_CN:-localhost}"
	openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
		-keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" \
		-subj "/CN=${TLS_CN:-localhost}"
fi
chown cyrus:mail "$CERT_DIR"/server.key "$CERT_DIR"/server.crt
chmod 640 "$CERT_DIR"/server.key
chmod 644 "$CERT_DIR"/server.crt

# Trust our own cert for TLS clients running inside this container (e.g.
# cyradm via docker exec). /usr/local/share/ca-certificates + /etc/ssl/certs
# live on the container's own root filesystem, not a volume, so this has to
# run on every boot, not just first boot. This has no effect on external
# clients (real mail clients, cyradm run from outside the container) - their
# own OS/trust store is unrelated to what's inside this container.
cp "$CERT_DIR/server.crt" /usr/local/share/ca-certificates/cyrus-imap-selfsigned.crt
update-ca-certificates >/dev/null

# /run is not persistent storage; recreate the sockets/proc dirs cyrus expects every boot.
mkdir -p /run/cyrus/proc /run/cyrus/lock /run/cyrus/socket
chown -R cyrus:mail /run/cyrus
chmod -R 750 /run/cyrus

mkdir -p /var/run/saslauthd
chown root:sasl /var/run/saslauthd
chmod 750 /var/run/saslauthd

# Mailbox store/spool volumes start empty; (re)initialize on first boot.
if [ ! -d /var/lib/cyrus/db ]; then
	echo "Initializing Cyrus mailbox store in /var/lib/cyrus and /var/spool/cyrus"
	cyrus makedirs --cleansquat
fi
chown -R cyrus:mail /var/lib/cyrus /var/spool/cyrus/mail

echo "Starting saslauthd against LDAP server $(grep '^ldap_servers:' /etc/saslauthd.conf | cut -d' ' -f2-)"
saslauthd -a ldap -O /etc/saslauthd.conf -n "${SASLAUTHD_THREADS:-5}" -m /var/run/saslauthd

for i in $(seq 1 20); do
	[ -S /var/run/saslauthd/mux ] && break
	sleep 0.5
done
if [ ! -S /var/run/saslauthd/mux ]; then
	echo "saslauthd did not create its socket, aborting" >&2
	exit 1
fi

echo "Starting Cyrus IMAP master"
exec /usr/sbin/cyrmaster -l 32 -C /etc/imapd.conf -M /etc/cyrus.conf
