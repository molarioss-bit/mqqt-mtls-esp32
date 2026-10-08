```bash
#!/bin/bash
set -e

echo "=========================================="
echo " MQTT Docker Certificate Deployment"
echo "=========================================="

# Directory containing this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Project root
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Certificate source
SOURCE="/certs"

# Docker Mosquitto certificate directory
DEST="$PROJECT_DIR/mosquitto/certs"

echo ""
echo "Project:     $PROJECT_DIR"
echo "Source:      $SOURCE"
echo "Destination: $DEST"
echo ""

# Check source certificates
echo "--- Checking certificates ---"

for FILE in ca.crt server.crt server.key; do
    if [ ! -f "$SOURCE/$FILE" ]; then
        echo "ERROR: Missing $SOURCE/$FILE"
        exit 1
    fi

    echo "OK: $FILE"
done

# Create destination directory if it doesn't exist
mkdir -p "$DEST"

echo ""
echo "--- Copying certificates ---"

cp "$SOURCE/ca.crt"     "$DEST/ca.crt"
cp "$SOURCE/server.crt" "$DEST/server.crt"
cp "$SOURCE/server.key" "$DEST/server.key"

# Set permissions
chmod 644 "$DEST/ca.crt"
chmod 644 "$DEST/server.crt"
chmod 644 "$DEST/server.key"

echo "Certificates copied successfully."

echo ""
echo "--- Verifying server certificate ---"

openssl verify \
    -CAfile "$DEST/ca.crt" \
    "$DEST/server.crt"

echo ""
echo "--- Installed files ---"
ls -l "$DEST"

echo ""
echo "=========================================="
echo " Deployment complete"
echo "=========================================="
```