#!/bin/bash

# Disable unattended-upgrades
sudo systemctl stop unattended-upgrades.service
sudo systemctl disable unattended-upgrades.service

# Function to check for dpkg/apt lock
wait_for_apt_locks() {
    echo "Checking for apt locks..."
    while lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || lsof /var/lib/apt/lists/lock >/dev/null 2>&1; do
        echo "Waiting for other software managers to finish..."
        sleep 5
    done
}

# Ensure script is run as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script needs to run as root."
    exit 1
fi

# Wait for apt locks to be released
wait_for_apt_locks

# Update and upgrade package
apt-get update && apt-get upgrade -y

# Install necessary package
apt-get install -y docker.io docker-compose git openssl

# Disable swap & add kernel settings
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Add kernel settings & Enable IP tables (CNI Prerequisites)
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

# Install containerd run time dependencies
apt-get update -y
apt-get install ca-certificates curl gnupg lsb-release -y

# Add Docker’s official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install containerd
apt-get update -y
apt-get install containerd.io -y

# Generate default configuration file for containerd
containerd config default > /etc/containerd/config.toml

# Update configure cgroup as systemd for containerd
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Restart and enable containerd service
systemctl restart containerd
systemctl enable containerd

# Installing kubeadm, kubelet and kubectl
apt-get update
apt-get install -y apt-transport-https ca-certificates curl

# Download the Google Cloud public signing key
curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

# Add the Kubernetes apt repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update apt package index, install kubelet, kubeadm and kubectl, and pin their version
apt-get update
apt-get install -y kubelet kubeadm kubectl || { echo "Installation failed"; exit 1; }
apt-mark hold kubelet kubeadm kubectl

# Enable and start kubelet service
systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet.service

# Initialize Kubeadm
kubeadm init
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

# apply network weave
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

# Install Kompose, used for converting docker-compose.yml
curl -L https://github.com/kubernetes/kompose/releases/download/v1.32.0/kompose-linux-amd64 -o kompose
chmod +x kompose
mv kompose /usr/local/bin/
#verify if weave is deployed successfully
kubectl get pods -A

# Installing Helm for Kubernetes Dashbaord
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Installing Kubernetes Dashboard via Helm installer
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard

# Fetch the name of the first node in the cluster
NODE_NAME=$(kubectl get nodes --no-headers | awk '{print $1; exit}')

# Apply the taint to the dynamically fetched node name
kubectl taint nodes $NODE_NAME node-role.kubernetes.io/control-plane:NoSchedule-

# Write and save a new file for token

cat <<EOF > k8s-dashboard-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF

# Create user
kubectl create -f k8s-dashboard-account.yaml

# Get token for Kubernetes-Dashboard at https://hostname -p 
kubectl -n kube-system create token admin-user

kubeadm token create --print-join-command

kubectl get nodes
CUSTOMER_ID="K012345"

# Clone the repository
mkdir -p "/root/${CUSTOMER_ID}_iotc" && cd "/root/${CUSTOMER_ID}_iotc"
git clone https://bitbucket.org/enocean-cloud/iotconnector-docs.git

# Navigate to the directory where docker-compose.yml is located
cd /root/${CUSTOMER_ID}_iotc/iotconnector-docs/deploy/local_deployment

# Create a directory for certificates
mkdir -p "/root/${CUSTOMER_ID}_iotc/certs"

# Generate self-signed certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.key" -out "/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.crt" -subj "/C=SE/ST=State/L=City/O=Organization/CN=localhost"

# Update docker-compose.yml with the new certificate paths
sed -i "s|../nginx/dev.localhost.crt|/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.crt|" docker-compose.yml
sed -i "s|../nginx/dev.localhost.key|/root/${CUSTOMER_ID}_iotc/certs/${CUSTOMER_ID}_dev.localhost.key|" docker-compose.yml

# Update docker-compose.yml file proxy name and user
sed -i 's/BASIC_AUTH_USERNAME=.*/BASIC_AUTH_USERNAME=admin/' docker-compose.yml
sed -i 's/BASIC_AUTH_PASSWORD=.*/BASIC_AUTH_PASSWORD=Random123/' docker-compose.yml

# Create localhost.ext file
CURRENT_IP=$(hostname -I | awk '{print $1}')
cat > "/root/${CUSTOMER_ID}_iotc/certs/localhost.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
subjectKeyIdentifier = hash
[alt_names]
DNS.1 = localhost
IP.1 = $CURRENT_IP
EOF

sleep 1m

# Get the current host primary IP address
HOST_IP=$(hostname -I | awk '{print $1}')

# Debug: Print the HOST_IP to verify it's being set correctly
echo "Detected HOST_IP: $HOST_IP"

# Check if HOST_IP is empty and abort if so
if [ -z "$HOST_IP" ]; then
  echo "No IP address detected. Please check your network configuration."
  exit 1
fi

# Export POD_NAME using kubectl to get the name of the Kubernetes dashboard pod
export POD_NAME=$(kubectl get pods -n kubernetes-dashboard -l "app.kubernetes.io/name=kubernetes-dashboard,app.kubernetes.io/instance=kubernetes-dashboard" -o jsonpath="{.items[0].metadata.name}")

# Echo the HTTPS URL with the dynamically fetched host IP
echo "https://$HOST_IP"

# Forward the port from the Kubernetes dashboard pod to the host, using the dynamically fetched host IP
kubectl -n kubernetes-dashboard port-forward $POD_NAME 8443:8443 --address $HOST_IP

# Optionally, you can echo the URL again for convenience
echo "https://$HOST_IP"
