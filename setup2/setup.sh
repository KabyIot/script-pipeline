#!/bin/bash

# Kontrollera om skriptet körs som root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Det här skriptet måste köras som root."
    exit 1
fi

# Kundidentifierare, exempelvis 'K012345'
CUSTOMER_ID="K012345"

# Uppdatera och uppgradera paket
apt-get update && apt-get upgrade -y

# Installera nödvändiga paket
apt-get install -y docker.io docker-compose git openssl

# Skapa en katalog för kundspecifika filer och gå till den katalogen
mkdir -p "/root/${CUSTOMER_ID}_iotc" && cd "/root/${CUSTOMER_ID}_iotc"

# Kloning av nödvändiga repositories (Anta att det är ett offentligt repo. För privata repos, konfigurera SSH-nycklar eller använd användarnamn/lösenord)
git clone https://bitbucket.org/enocean-cloud/iotconnector-docs.git

# Gå till katalogen där docker-compose.yml finns
cd iotconnector-docs/deploy/local_deployment

# Skapa en katalog för certifikat
mkdir -p "/root/${CUSTOMER_ID}_iotc/certs"

# Generera självsignerade certifikat
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.key" -out "/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.crt" -subj "/C=SE/ST=State/L=City/O=Organization/CN=localhost"

# Anpassa docker-compose.yml med kundunika parametrar
sed -i "s/secret-proxy-certificate/file: \/root\/${CUSTOMER_ID}_iotc\/certs\/${CUSTOMER_ID}_dev.localhost.crt/" docker-compose.yml
sed -i "s/secret-proxy-key/file: \/root\/${CUSTOMER_ID}_iotc\/certs\/${CUSTOMER_ID}_dev.localhost.key/" docker-compose.yml

# Använd sed eller annat verktyg för att sätta miljövariabler och andra kundunika parametrar i docker-compose.yml

# Starta Docker containers
docker-compose up -d

# Kontrollera status på containrarna
docker-compose ps

echo "Installationen är klar. Kontrollera output ovan för containerstatus."

