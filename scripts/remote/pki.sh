#!/usr/bin/env bash
# Runs ON node-2 as root (via make converge). Idempotent private PKI:
#   /etc/cn-pki/ca.crt, ca.key     private CA            (created once)
#   /etc/cn-pki/tls.crt, tls.key   server cert app/api   (re-issued only if missing,
#                                  not signed by the CA, wrong names or < 30 days left)
# Prints "ok" or "changed" on stdout; details on stderr.
set -euo pipefail
TEAM="$1"; DOMAIN="$2"
D=/etc/cn-pki
mkdir -p "$D"; chmod 700 "$D"; cd "$D"
state=ok

if [ ! -s ca.key ] || [ ! -s ca.crt ]; then
  echo "creating private CA '$TEAM Private CA'" >&2
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 -sha256 \
    -keyout ca.key -out ca.crt -subj "/CN=$TEAM Private CA" 2>/dev/null
  rm -f tls.crt
  state=changed
fi

valid=1
if [ ! -s tls.crt ] || [ ! -s tls.key ]; then valid=0
elif ! openssl verify -CAfile ca.crt tls.crt >/dev/null 2>&1; then valid=0
elif ! openssl x509 -in tls.crt -noout -checkend 2592000 >/dev/null; then valid=0
elif ! openssl x509 -in tls.crt -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:app.$DOMAIN, DNS:api.$DOMAIN"; then valid=0
fi

if [ "$valid" = 0 ]; then
  echo "issuing server certificate for app.$DOMAIN, api.$DOMAIN" >&2
  openssl req -newkey rsa:2048 -nodes -keyout tls.key -out tls.csr -subj "/CN=app.$DOMAIN" 2>/dev/null
  cat > ext.cnf <<X
subjectAltName   = DNS:app.$DOMAIN, DNS:api.$DOMAIN
basicConstraints = CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
X
  openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 397 -sha256 -out tls.crt -extfile ext.cnf 2>/dev/null
  state=changed
fi
chmod 600 ca.key tls.key
echo "$state"
