<?php

// Cyrus's TLS cert is self-signed, and its CN won't match the Docker network
// hostname (cyrus-imap) we connect to it as - so both peer and peer-name
// verification need to be off, or the connection fails before auth is even
// attempted. Pragmatic for now; revisit if a real CA-signed cert is ever
// used (same posture as cyradm --cafile / the cyrus-imap container's own
// ca-certificates trust-store addition elsewhere in this repo).
$config['imap_conn_options'] = [
    'ssl' => [
        'verify_peer'      => false,
        'verify_peer_name' => false,
    ],
];
