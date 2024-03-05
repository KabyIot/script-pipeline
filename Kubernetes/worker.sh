#!/bin/bash

## Set the a new hostname for worker node 1 vm and worker node 2 vm or else it will not work with the masternode, if they have same hostname, change it with this command :
sudo hostnamectl set-hostname worker1

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
sudo apt-get install -y apt-transport-https ca-certificates curl

# Download the Google Cloud public signing key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update apt package index, install kubelet, kubeadm and kubectl, and pin their version

sudo apt-mark unhold kubelet kubeadm kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Enable and start kubelet service
systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet.service

sleep 10s

# put below the real "kubeadm join token", the  Worker node will join the masterNode(Cluster) after installation is done.

kubeadm join 197.128.23.103:6443 --token d98h3k.gap9x0dfg05m2xw2 --discovery-token-ca-cert-hash sha256:23ee0bf9f36a7a6a801755f158335a5865f59440be324edf1f0be3412 

## restart kubelet and containerd on worker vm.

sleep 20s
sudo systemctl restart kubelet
sudo systemctl restart containerd
