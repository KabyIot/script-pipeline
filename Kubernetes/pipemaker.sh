#!/bin/bash

# Define the file path for the namespace name
NAMESPACE_FILE="namespace_name.txt"

# Read the namespace name from the file, if it exists
if [ -f "$NAMESPACE_FILE" ]; then
  NAMESPACE_NAME=$(cat "$NAMESPACE_FILE")
else
  echo "Namespace file $NAMESPACE_FILE does not exist. Exiting."
  exit 1
fi

# Check if the namespace name is not empty
if [ -z "$NAMESPACE_NAME" ]; then
  echo "Namespace name is empty. Please provide a valid name in $NAMESPACE_FILE."
  exit 1
fi

# Check if the namespace exists, and create it if it does not
if ! kubectl get namespace "${NAMESPACE_NAME}" > /dev/null 2>&1; then
  echo "Namespace ${NAMESPACE_NAME} not found. Creating it..."
  kubectl create namespace "${NAMESPACE_NAME}"
fi

# Define the namespace directory path
namespace_dir="./${NAMESPACE_NAME}"
# Ensure the customer-specific directory exists
mkdir -p "${namespace_dir}"

# Function to create PV files with specific configurations
create_pv() {
  local name="$1"
  local pv_name="${name}-volume-${NAMESPACE_NAME}"  # Include namespace in the PV name
  local pv_file="${namespace_dir}/${pv_name}.yaml"  # Create PV file inside namespace directory

  cat <<EOF >"${pv_file}"
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${pv_name}
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 100Mi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/data/${NAMESPACE_NAME}/${name}"
EOF
}

create_pvc() {
  local name="$1"
  local pvc_name="${name}-${NAMESPACE_NAME}"  # Include namespace in the PVC name
  local pvc_file="${namespace_dir}/${pvc_name}.yaml"  # Create PVC file inside namespace directory

  cat <<EOF >"${pvc_file}"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: $NAMESPACE_NAME
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
EOF
}

# Function to create a Network Policy that allows traffic within the same namespace
create_network_policy() {
  cat <<EOF >"${namespace_dir}/allow-same-namespace-${NAMESPACE_NAME}.yaml"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace-${NAMESPACE_NAME}
  namespace: $NAMESPACE_NAME
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF
}

# Names for the PVs and PVCs to be created
names=("api-claim0" "fluentd-claim0" "fluentd-claim1" "redis-volume")

# Create PV and PVC files for each name
for name in "${names[@]}"; do
  create_pv "$name"
  create_pvc "$name"
done

# Create Network Policy
create_network_policy

# Apply the Network Policy and all resources
kubectl apply -f "${namespace_dir}/"

# Additional YAML files to update with the namespace and prepare for application
FILES=(
  "ingress-service.yaml"
  "mqtt-service.yaml"
  "proxy-service.yaml"
  "secret-proxy-key-secret.yaml"
  "engine-deployment.yaml"
  "integration-deployment.yaml"
  "rabbitmq-deployment.yaml"
  "api-deployment.yaml"
  "fluentd-deployment.yaml"
  "rabbitmq-service.yaml"
  "redis-service.yaml"
  "api-service.yaml"
  "ingress-deployment.yaml"
  "mqtt-deployment.yaml"
  "proxy-deployment.yaml"
  "redis-deployment.yaml"
  "secret-proxy-certificate-secret.yaml"
)

# Organize and apply the additional Kubernetes configurations
prepare_and_apply_resources() {
  for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
      cp "$file" "${namespace_dir}/"
    else
      echo "Warning: File '$file' not found and will not be copied."
    fi
  done

  # Apply all configurations in the namespace directory
  kubectl apply -f "${namespace_dir}/"
}

prepare_and_apply_resources

echo "PV, PVC files, and network policies have been created, and existing files updated with namespace $NAMESPACE_NAME successfully. Additional configurations have been organized and applied."
