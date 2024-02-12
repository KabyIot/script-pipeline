#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Update and upgrade packages
apt-get update && apt-get upgrade -y

# Install necessary packages
apt-get install -y docker.io docker-compose git openssl

# Clone the repository
cd /root
git clone https://bitbucket.org/enocean-cloud/iotconnector-docs.git

# Install and configure self-signed certificates
mkdir -p /export && cd /export

# Generate CA Key and Certificate
openssl genrsa -des3 -out /export/myCA.key 2048
openssl req -x509 -new -nodes -key /export/myCA.key -sha256 -days 1825 -out /export/myCA.pem

# Generate server key and CSR
openssl genrsa -out /export/dev.localhost.key 2048
openssl req -new -key /export/dev.localhost.key -out /export/dev.localhost.csr

# Create localhost.ext file
CURRENT_IP=$(hostname -I | awk '{print $1}')
cat > /export/localhost.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
subjectKeyIdentifier = hash

[alt_names]
DNS.1 = localhost
IP.1 = $CURRENT_IP
EOF

# Generate server certificate
openssl x509 -req -in /export/dev.localhost.csr -CA /export/myCA.pem -CAkey /export/myCA.key -CAcreateserial -out /export/dev.localhost.crt -days 825 -sha256 -extfile /export/localhost.ext

# Update docker-compose.yml file
cd /root/iotconnector-docs/deploy/local_deployment
sed -i 's/BASIC_AUTH_USERNAME=.*/BASIC_AUTH_USERNAME=admin/' docker-compose.yml
sed -i 's/BASIC_AUTH_PASSWORD=.*/BASIC_AUTH_PASSWORD=Random123/' docker-compose.yml

# Update secrets in docker-compose.yml
sed -i 's|../nginx/dev.localhost.crt|/export/dev.localhost.crt|' docker-compose.yml
sed -i 's|../nginx/dev.localhost.key|/export/dev.localhost.key|' docker-compose.yml

# Start the docker containers
docker-compose up -d

# Check the status of the containers
docker-compose ps

echo "Setup complete. Check above output for container status."
