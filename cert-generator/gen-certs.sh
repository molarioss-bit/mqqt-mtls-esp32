#!/bin/sh
set -e

echo "=== MQTT mTLS Certificate Setup ==="
echo "1) Generate new CA + server + client certificates"
echo "2) I already have certificates, just validate/copy them"
echo "3) Generate a new client certificate signed by an existing CA"
read -p "Choose [1/2/3]: " CHOICE

mkdir -p /certs
cd /certs

if [ "$CHOICE" = "2" ]; then
  echo ""
  echo "Place your existing files in the 'existing' folder before running this."
  echo "Expected: ca.crt, server.crt, server.key, <client>.crt, <client>.key"
  echo ""

  if [ ! -d /existing ]; then
    echo "ERROR: /existing folder not found. Mount your certs folder to /existing and retry."
    exit 1
  fi

  cp /existing/*.crt /certs/ 2>/dev/null || true
  cp /existing/*.key /certs/ 2>/dev/null || true

  for f in /certs/*.crt; do
    base=$(basename "$f" .crt)
    if [ -f "/certs/$base.key" ]; then
      cert_mod=$(openssl x509 -noout -modulus -in "$f" | openssl md5)
      key_mod=$(openssl rsa -noout -modulus -in "/certs/$base.key" | openssl md5)
      if [ "$cert_mod" = "$key_mod" ]; then
        echo "OK: $base.crt matches $base.key"
      else
        echo "WARNING: $base.crt does NOT match $base.key"
      fi
    fi
  done

  chmod 644 /certs/*.key /certs/*.crt 2>/dev/null || true
  echo "--- Done. Existing certificates copied into /certs ---"
  ls -l /certs
  exit 0
fi

if [ "$CHOICE" = "3" ]; then
  echo ""
  echo "This requires the existing CA (ca.crt and ca.key) mounted at /existing."
  echo ""

  if [ ! -f /existing/ca.crt ] || [ ! -f /existing/ca.key ]; then
    echo "ERROR: /existing/ca.crt and /existing/ca.key are both required. Mount them and retry."
    exit 1
  fi

  cp /existing/ca.crt /certs/ca.crt
  cp /existing/ca.key /certs/ca.key

  read -p "New client identifier (e.g. esp32-02): " CLIENT
  read -p "Validity in days [825]: " DAYS
  DAYS=${DAYS:-825}

  echo "--- Generating client certificate for $CLIENT, signed by existing CA ---"
  openssl genrsa -out "$CLIENT.key" 2048
  openssl req -new -key "$CLIENT.key" -subj "/CN=$CLIENT" -out "$CLIENT.csr"
  openssl x509 -req -in "$CLIENT.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days "$DAYS" \
    -extfile <(printf "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth") \
    -out "$CLIENT.crt"

  rm -f "$CLIENT.csr" *.srl ca.key
  chmod 644 /certs/*.key /certs/*.crt 2>/dev/null || true
  echo "--- Done. $CLIENT.crt and $CLIENT.key are in /certs ---"
  ls -l /certs
  exit 0
fi

# ---- Option 1: generate everything new ----
echo "=== Generating new CA + server + client certificates ==="
read -p "Broker hostname or IP (used in server cert): " SERVER
read -p "Client identifier (e.g. esp32): " CLIENT
read -p "Validity in days [825]: " DAYS
DAYS=${DAYS:-825}

echo "--- Generating CA ---"
openssl genrsa -out ca.key 2048
openssl req -x509 -new -key ca.key -days 3650 -subj "/CN=MyProjectCA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out ca.crt

echo "--- Generating server certificate for $SERVER ---"
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=$SERVER" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days "$DAYS" \
  -extfile <(printf "subjectAltName=IP:%s\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth" "$SERVER") \
  -out server.crt

echo "--- Generating client certificate for $CLIENT ---"
openssl genrsa -out "$CLIENT.key" 2048
openssl req -new -key "$CLIENT.key" -subj "/CN=$CLIENT" -out "$CLIENT.csr"
openssl x509 -req -in "$CLIENT.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days "$DAYS" \
  -extfile <(printf "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth") \
  -out "$CLIENT.crt"

rm -f *.csr *.srl
chmod 644 /certs/*.key /certs/*.crt 2>/dev/null || true
echo "--- Done. Files are in the mounted /certs folder ---"
ls -l /certs