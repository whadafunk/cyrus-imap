FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
		cyrus-imapd \
		cyrus-admin \
		cyrus-clients \
		sasl2-bin \
		libsasl2-modules-ldap \
		openssl \
	&& rm -rf /var/lib/apt/lists/*

# bookworm-slim's /etc/services has no "lmtp" entry, so cyrus.conf's
# listen="0.0.0.0:lmtp" service-name lookup fails and master silently
# disables that service. Add the IANA-assigned port (24/tcp).
RUN echo "lmtp		24/tcp		# Local Mail Transfer Protocol" >> /etc/services

# Test users for shadow-based saslauthd auth. Dev/test only - weak throwaway
# password, baked directly into an image layer. Do not carry this into any
# real deployment; drop this block once real auth (LDAP) is wired up.
RUN useradd -M admin && echo "admin:pass123" | chpasswd \
	&& useradd -M daniel && echo "daniel:pass123" | chpasswd

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# IMAP, IMAPS
EXPOSE 143 993

VOLUME ["/var/lib/cyrus", "/var/spool/cyrus", "/etc/cyrus/tls"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
