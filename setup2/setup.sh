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

# Säkerhetskopiera ursprungliga docker-compose.yml
cp docker-compose.yml docker-compose.yml.bak

# Uppdatera docker-compose.yml med de nya certifikatvägarna
sed -i "s|../nginx/dev.localhost.crt|/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.crt|" docker-compose.yml
sed -i "s|../nginx/dev.localhost.key|/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.key|" docker-compose.yml

# Updatera docker-compose.yml fil
cd /root/iotconnector-docs/deploy/local_deployment
sed -i 's/BASIC_AUTH_USERNAME=.*/BASIC_AUTH_USERNAME=admin/' docker-compose.yml
sed -i 's/BASIC_AUTH_PASSWORD=.*/BASIC_AUTH_PASSWORD=Random123/' docker-compose.yml

# Kontrollera om det finns specifika radnummer eller strukturer som behöver ändras, och använd sed eller annat verktyg försiktigt

# Starta Docker containers
docker-compose up -d

# Kontrollera status på containrarna
docker-compose ps

echo "Installationen är klar. Kontrollera output ovan för containerstatus."
