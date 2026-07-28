#!/bin/bash
set -euo pipefail

# imapd.conf and cyrus.conf are plain, static files bind-mounted in by
# docker-compose (see docker-compose.yml) - no rendering needed.
[ -f /etc/imapd.conf ] || { echo "/etc/imapd.conf not found - mount config/imapd.conf there" >&2; exit 1; }
[ -f /etc/cyrus.conf ] || { echo "/etc/cyrus.conf not found - mount config/cyrus.conf there" >&2; exit 1; }

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

echo "Starting saslauthd (shadow)"
saslauthd -a shadow -n "${SASLAUTHD_THREADS:-5}" -m /var/run/saslauthd

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
