#!/bin/bash
# common.sh

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Det här skriptet måste köras som root."
    exit 1
fi

#2) Disable swap & add kernel settings

swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab


#3) Add  kernel settings & Enable IP tables(CNI Prerequisites)

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

#4) Install containerd run time

#To install containerd, first install its dependencies.

apt-get update -y
apt-get install ca-certificates curl gnupg lsb-release -y

#Note: We are not installing Docker Here.Since containerd.io package is part of docker apt repositories hence we added docker repository & it's key to download and install containerd.
# Add Docker’s official GPG key:
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

#Use follwing command to set up the repository:

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install containerd

apt-get update -y
apt-get install containerd.io -y

# Generate default configuration file for containerd

#Note: Containerd uses a configuration file located in /etc/containerd/config.toml for specifying daemon level options.
#The default configuration can be generated via below command.

containerd config default > /etc/containerd/config.toml

# Run following command to update configure cgroup as systemd for contianerd.

sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Restart and enable containerd service

systemctl restart containerd
systemctl enable containerd

#5) Installing kubeadm, kubelet and kubectl

# Update the apt package index and install packages needed to use the Kubernetes apt repository:

apt-get update
apt-get install -y apt-transport-https ca-certificates curl

# Download the Google Cloud public signing key:

curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

# Add the Kubernetes apt repository:

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update apt package index, install kubelet, kubeadm and kubectl, and pin their version:

apt-get update
apt-get install -y kubelet kubeadm kubectl

# apt-mark hold will prevent the package from being automatically upgraded or removed.

apt-mark hold kubelet kubeadm kubectl

# Enable and start kubelet service

systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet.service

# Initialize Kubeadm
kubeadm init

mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

curl -L https://github.com/kubernetes/kompose/releases/download/v1.32.0/kompose-linux-amd64 -o kompose
chmod +x kompose
mv kompose /usr/local/bin/
#verify if weave is deployed successfully
kubectl get pods -A

kubeadm token create --print-join-command

kubectl get nodes

# Install git if not present
if ! command -v git &> /dev/null; then
    apt-get update && apt-get install git -y
fi

CUSTOMER_ID="K012345"

# Clone the repository

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

# Create localhost.ext file
CURRENT_IP=$(hostname -I | awk '{print $1}')
cat > /root/${CUSTOMER_ID}_iotc/certs/localhost.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
subjectKeyIdentifier = hash

[alt_names]
DNS.1 = localhost
IP.1 = $CURRENT_IP
EOF




