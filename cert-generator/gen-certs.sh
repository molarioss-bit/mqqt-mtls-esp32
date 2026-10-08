#!/bin/sh
set -e

echo "=== MQTT mTLS Certificate Generator ==="



mkdir -p /certs
cd /certs

echo ""
echo ""
echo "++++++++++ Generating CA ++++++++++"
echo ""
echo ""

# Generating the CA key
openssl genrsa -out ca.key 2048  

# This creates an X.509 certificate valid for 10 years
openssl req -x509 -new -key ca.key -days 3650 -out ca.crt

echo ""
echo ""
echo "++++++++++ Generating server certificate ++++++++++"
echo ""
echo ""

#Server key
openssl genrsa -out server.key 2048

#Here with this we making a request to make the certificate, after that we need the CA approval
openssl req -new -key server.key -out server.csr

#x.509 certificate signed by the CA
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt

echo "++++++++++ Generating client certificate ++++++++++"
echo ""
echo ""

#default client name is client
read -p "Enter your client name (used for namine ; "client".cert): " CLIENT
CLIENT=${CLIENT:-client}

#default validity day is 825
read -p "Validity in days [825]: " DAYS
DAYS=${DAYS:-825}

#Client key
openssl genrsa -out "$CLIENT.key" 2048

#Client request for the certificate

#Request +
openssl req -new -key "$CLIENT.key" -out "$CLIENT.csr"
openssl x509 -req -in "$CLIENT.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -days "$DAYS" -out "$CLIENT.crt"


#Cleaning
rm -f *.csr *.srl
chmod 644 /certs/*.key /certs/*.crt
echo "_-_-_-_-_ Done. Files are in the mounted /certs folder _-_-_-_-_ "
ls -l /certs

echo ""
echo "the certificates are in /certs"
