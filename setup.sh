#!/bin/bash

# Step 1: This step is manual and involves creating a new Ubuntu Server 22.04 instance.

# Step 2: Elevate to root, script should be run with sudo or as root

# Step 3: Update and Upgrade the System
apt-get update && apt-get upgrade -y

# Step 4: Install Docker
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce

# Step 5: Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Step 6: Clone the Git Repository
git clone https://bitbucket.org/enocean-cloud/iotconnector-docs.git

# Step 7: Generate Self-signed Certificates
# Assuming the current working directory is suitable for generating and storing certificates
mkdir -p export && cd export

# Use OpenSSL to generate the CA and certificates
openssl genrsa -des3 -out myCA.key 2048
openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem
openssl genrsa -out dev.localhost.key 2048
openssl req -new -key dev.localhost.key -out dev.localhost.csr

# Create localhost.ext file
cat <<EOF > localhost.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
subjectKeyIdentifier = hash

[alt_names]
DNS.1 = localhost
IP.1 = 192.168.1.2
EOF

# Generate the final certificate
openssl x509 -req -in dev.localhost.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial -out dev.localhost.crt -days 825 -sha256 -extfile localhost.ext

echo "Setup completed successfully."
