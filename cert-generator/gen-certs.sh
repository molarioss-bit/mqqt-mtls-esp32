#!/bin/sh
set -e

echo "=== MQTT mTLS Certificate Generator ==="
read -p "Broker hostname or IP (used in server cert): " SERVER
read -p "Client identifier (e.g. esp32): " CLIENT
read -p "Validity in days [825]: " DAYS
DAYS=${DAYS:-825}

mkdir -p /certs
cd /certs

echo "--- Generating CA ---"
openssl genrsa -out ca.key 2048
openssl req -x509 -new -key ca.key -days 3650 -subj "/CN=MyProjectCA" -out ca.crt

echo "--- Generating server certificate for $SERVER ---"
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=$SERVER" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days "$DAYS" -extfile <(echo "subjectAltName=IP:$SERVER") -out server.crt

echo "--- Generating client certificate for $CLIENT ---"
openssl genrsa -out "$CLIENT.key" 2048
openssl req -new -key "$CLIENT.key" -subj "/CN=$CLIENT" -out "$CLIENT.csr"
openssl x509 -req -in "$CLIENT.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days "$DAYS" -out "$CLIENT.crt"

rm -f *.csr *.srl
echo "--- Done. Files are in the mounted /certs folder ---"
ls -l /certs

echo "--- Setting permissions ---"
chmod 644 /certs/*.key
chmod 644 /certs/*.crt

echo "--- Done. Files are in the mounted /certs folder ---"
ls -l /certs