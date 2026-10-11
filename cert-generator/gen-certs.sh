#!/bin/sh
# MQTT mTLS certificate generator (POSIX sh, runs in Alpine/busybox)
#
# Run it from the repo root with the whole repo mounted:
#   docker run -it --rm -v "${PWD}:/repo" cert-generator
#
# Layout it manages:
#   certs/                          master copy of everything (git-ignored, keep ca.key here only)
#   mqtt-broker/mosquitto/certs/    ca.crt, server.crt, server.key   (copied automatically)
#   esp-firmware/data/              ca.crt, esp.crt, esp.key         (copied automatically)
#
# Why the extensions below matter: mbedTLS (ESP32) enforces X.509 extensions
# (basicConstraints, keyUsage, extendedKeyUsage) strictly, while OpenSSL
# (Mosquitto) does not. Certificates that "work" on the broker can still be
# rejected by the ESP32. The server also needs a subjectAltName: Node-based
# tools (MQTT Explorer) only match IP hosts against "IP:" entries, while
# mbedTLS matches the hostname text against "DNS:" entries.
set -e

die() { echo "ERROR: $1" >&2; exit 1; }

# ---------- locations ----------

REPO="${REPO:-/repo}"
[ -d "$REPO/mqtt-broker" ] || die "mqtt-broker/ not found in $REPO. Run from the repo root with: -v \"\${PWD}:/repo\""

CERT_DIR="${CERT_DIR:-$REPO/certs}"
BROKER_DIR="${BROKER_DIR:-$REPO/mqtt-broker/mosquitto/certs}"
if [ -z "$FW_DIR" ]; then
  for d in esp-firmware esp32-firmware; do
    if [ -d "$REPO/$d" ]; then FW_DIR="$REPO/$d/data"; break; fi
  done
fi
# The firmware folder is optional: without it, only the broker is deployed and
# the ESP32 files stay in certs/ for you to copy by hand.

mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# Temporary files (requests, extension files, serial counters) are removed on
# every exit, including after an error. Without ca.srl, OpenSSL picks a random
# serial number for each new certificate.
trap 'rm -f "$CERT_DIR"/*.csr "$CERT_DIR"/*.ext "$CERT_DIR"/*.srl' EXIT

# ---------- helpers ----------

# ask "Prompt" "default"  -> prints the answer (prompt goes to stderr)
ask() {
  printf "%s [%s]: " "$1" "$2" >&2
  read -r _v || _v=""
  echo "${_v:-$2}"
}

# letters, digits, dot, underscore, dash only (names end up in file names)
valid_name() {
  case "$1" in
    ""|*[!A-Za-z0-9_.-]*) return 1 ;;
  esac
  return 0
}

need_ca() {
  [ -f ca.crt ] && [ -f ca.key ] || die "ca.crt / ca.key not found. Run option 1 first."
}

# check_pair CERT KEY: the certificate must belong to the private key
check_pair() {
  c=$(openssl x509 -noout -modulus -in "$1" | openssl md5)
  k=$(openssl rsa  -noout -modulus -in "$2" | openssl md5)
  [ "$c" = "$k" ] || die "$1 does not match $2 (wrong CSR or wrong key?)"
  echo "  OK  $1 matches $2"
}

# sign CSR CRT EXTFILE DAYS: sign a request with our CA
sign() {
  openssl x509 -req -sha256 -in "$1" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days "$4" -extfile "$3" -out "$2"
}

# lint_cert FILE KIND: warn when the extensions mbedTLS needs are missing
lint_cert() {
  txt=$(openssl x509 -in "$1" -noout -text)
  bad=0
  need() { echo "$txt" | grep -q "$1" || { echo "  WARN $1: missing $2"; bad=1; }; }
  case "$2" in
    ca)     need "CA:TRUE" "basicConstraints CA:TRUE"
            need "Certificate Sign" "keyUsage keyCertSign" ;;
    server) need "CA:FALSE" "basicConstraints CA:FALSE"
            need "Digital Signature" "keyUsage digitalSignature"
            need "TLS Web Server Authentication" "extendedKeyUsage serverAuth"
            need "Subject Alternative Name" "subjectAltName" ;;
    client) need "CA:FALSE" "basicConstraints CA:FALSE"
            need "Digital Signature" "keyUsage digitalSignature"
            need "TLS Web Client Authentication" "extendedKeyUsage clientAuth" ;;
  esac
  [ "$bad" = 0 ] && echo "  OK  $1 has the expected $2 extensions"
  return 0
}

# ---------- deployment (copies from the master folder) ----------

deploy_broker() {
  mkdir -p "$BROKER_DIR"
  cp ca.crt server.crt server.key "$BROKER_DIR/"
  chmod 644 "$BROKER_DIR/server.key" "$BROKER_DIR/server.crt" "$BROKER_DIR/ca.crt"
  echo "  -> broker files copied to ${BROKER_DIR#$REPO/}  (ca.crt, server.crt, server.key)"
}

# deploy_device NAME: the firmware always reads ca.crt, esp.crt, esp.key
deploy_device() {
  if [ -z "$FW_DIR" ]; then
    echo "  -> no esp-firmware/ folder next to this one, so nothing was copied."
    echo "     Copy by hand into your firmware's data/ folder:"
    echo "       certs/ca.crt  ->  ca.crt"
    echo "       certs/$1.crt  ->  esp.crt"
    echo "       certs/$1.key  ->  esp.key"
    return 0
  fi
  mkdir -p "$FW_DIR"
  cp ca.crt "$FW_DIR/ca.crt"
  cp "$1.crt" "$FW_DIR/esp.crt"
  cp "$1.key" "$FW_DIR/esp.key"
  echo "  -> ESP32 files copied to ${FW_DIR#$REPO/}  (ca.crt, esp.crt, esp.key)"
}

# ---------- generators ----------

make_ca() {
  if [ -f ca.key ]; then
    a=$(ask "ca.key already exists. Overwrite the CA? Old certs will stop working (yes/no)" "no")
    [ "$a" = "yes" ] || { echo "Keeping the existing CA."; return 0; }
  fi
  echo "--- Generating CA ---"
  openssl genrsa -out ca.key 2048
  openssl req -x509 -new -sha256 -key ca.key -days 3650 -out ca.crt \
    -subj "/CN=mqtt-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
  chmod 600 ca.key      # the CA key must never leave the certs/ folder
  lint_cert ca.crt ca
}

make_server() {
  need_ca
  echo "--- Generating server certificate ---"
  name=$(ask "Broker DNS name (CN and SAN)" "mqtt-broker")
  valid_name "$name" || die "invalid name '$name'"
  ip=$(ask "Broker IP address (empty to skip)" "")
  days=$(ask "Validity in days" "825")

  san="DNS:$name"
  # The IP is added twice on purpose: as IP: for Node/OpenSSL clients and as
  # DNS: because mbedTLS compares the hostname text with DNS entries only.
  [ -n "$ip" ] && san="$san,DNS:$ip,IP:$ip"

  openssl genrsa -out server.key 2048
  openssl req -new -key server.key -out server.csr -subj "/CN=$name"
  printf "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\n" "$san" > server.ext
  sign server.csr server.crt server.ext "$days"
  rm -f server.csr server.ext
  chmod 644 server.key  # the broker container must be able to read it
  check_pair server.crt server.key
  lint_cert server.crt server
  echo "  SAN: $san"
  deploy_broker
}

make_client() {
  need_ca
  echo "--- Generating client certificate ---"
  name=$(ask "Client name (CN, files are NAME.crt / NAME.key)" "client")
  valid_name "$name" || die "invalid name '$name'"
  [ "$name" = "ca" ] || [ "$name" = "server" ] && die "'$name' is reserved"
  [ -f "$name.key" ] && {
    a=$(ask "$name.key exists. Overwrite? (yes/no)" "no")
    [ "$a" = "yes" ] || { echo "Skipped."; return 0; }
  }
  echo ""
  echo "Is this client certificate for the ESP32?"
  if [ -n "$FW_DIR" ]; then
    echo "  y = YES: copy ca.crt, $name.crt and $name.key into ${FW_DIR#$REPO/}/"
    echo "          as ca.crt, esp.crt and esp.key (the names the firmware reads)."
  else
    echo "  y = YES: no firmware folder found, so the script will show you which"
    echo "          files to copy by hand into your firmware's data/ folder."
  fi
  echo "  n = NO:  keep the files only in ${CERT_DIR#$REPO/}/ (use this for MQTT Explorer"
  echo "          or any other client)."
  while true; do
    is_esp=$(ask "Copy to the ESP32 firmware? (y/n)" "y")
    case "$is_esp" in
      y|Y|yes) is_esp=y; break ;;
      n|N|no)  is_esp=n; break ;;
      *) echo "Please answer y or n." ;;
    esac
  done
  days=$(ask "Validity in days" "825")

  openssl genrsa -out "$name.key" 2048
  openssl req -new -key "$name.key" -out "$name.csr" -subj "/CN=$name"
  printf "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=clientAuth\n" > "$name.ext"
  sign "$name.csr" "$name.crt" "$name.ext" "$days"
  rm -f "$name.csr" "$name.ext"
  chmod 644 "$name.key"
  check_pair "$name.crt" "$name.key"
  lint_cert "$name.crt" client
  if [ "$is_esp" = "y" ]; then
    deploy_device "$name"
  else
    echo "  -> files for this client stay in ${CERT_DIR#$REPO/}/  ($name.crt, $name.key, ca.crt)"
  fi
}

# Validate everything in certs/ (pairs, chain, extensions) and check that the
# copies in the broker and firmware folders are up to date.
validate_existing() {
  echo "--- Validating certificates in ${CERT_DIR#$REPO/} ---"
  [ -f ca.crt ] || die "ca.crt not found"
  lint_cert ca.crt ca
  for crt in *.crt; do
    base=${crt%.crt}
    [ "$base" = "ca" ] && continue
    [ -f "$base.key" ] || { echo "  SKIP $crt (no $base.key)"; continue; }
    check_pair "$crt" "$base.key"
    openssl verify -CAfile ca.crt "$crt" > /dev/null || die "$crt is not signed by ca.crt"
    echo "  OK  $crt is signed by ca.crt"
    case "$base" in
      server*) lint_cert "$crt" server ;;
      *)       lint_cert "$crt" client ;;
    esac
  done

  echo "--- Checking deployed copies ---"
  for f in ca.crt server.crt server.key; do
    if [ ! -f "$BROKER_DIR/$f" ]; then echo "  WARN broker folder is missing $f"
    elif cmp -s "$f" "$BROKER_DIR/$f"; then echo "  OK  broker $f is up to date"
    else echo "  WARN broker $f differs from certs/$f (run option 2 to redeploy)"; fi
  done
  if [ -z "$FW_DIR" ]; then
    echo "  SKIP firmware folder not found (copy the ESP32 files by hand)"
  else
    for f in ca.crt esp.crt esp.key; do
      [ -f "$FW_DIR/$f" ] || echo "  WARN firmware data folder is missing $f"
    done
  fi
  if [ -n "$FW_DIR" ] && [ -f "$FW_DIR/esp.crt" ] && [ -f "$FW_DIR/esp.key" ]; then
    check_pair "$FW_DIR/esp.crt" "$FW_DIR/esp.key"
    openssl verify -CAfile ca.crt "$FW_DIR/esp.crt" > /dev/null \
      && echo "  OK  firmware esp.crt is signed by the current CA" \
      || echo "  WARN firmware esp.crt is NOT signed by the current CA (run option 3 again)"
  fi
}

# ---------- menu ----------

echo "=== MQTT mTLS Certificate Generator ==="
echo "Master folder: ${CERT_DIR#$REPO/}"
while true; do
  echo ""
  echo "1) New CA + server + first client certificate"
  echo "2) New server certificate only (e.g. the broker IP changed)"
  echo "3) New client certificate (ESP32, MQTT Explorer, another device)"
  echo "4) Validate certificates and deployed copies"
  echo "5) Quit"
  choice=$(ask "Choose" "5")
  case "$choice" in
    1) make_ca; make_server; make_client ;;
    2) make_server ;;
    3) make_client ;;
    4) validate_existing ;;
    5) break ;;
    *) echo "Unknown option." ;;
  esac
done

cat <<'MSG'

Next steps:
  - Broker:  docker compose restart mosquitto   (from mqtt-broker/)
  - ESP32:   pio run -t uploadfs                (from the firmware folder)
  - MQTT Explorer / other clients: use certs/ca.crt, certs/<name>.crt, certs/<name>.key
NEVER copy ca.key anywhere: it can sign certificates for any device.
MSG
