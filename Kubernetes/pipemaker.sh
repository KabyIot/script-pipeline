#!/bin/bash
 
# Check for yq and install if not found
if ! command -v yq &> /dev/null; then
    echo "yq could not be found. Attempting to install it..."
    snap install yq
    if ! command -v yq &> /dev/null; then
        echo "Failed to install yq. Please install it manually."
        exit 1
    fi
else
    echo "yq is already installed."
fi
 
echo "Current working directory: $(pwd)"
 
# Directly define the namespace name here
NAMESPACE_NAME="customer3003"
 
# Check if the namespace exists, and create it if it does not
if ! kubectl get namespace "${NAMESPACE_NAME}" > /dev/null 2>&1; then
    echo "Namespace ${NAMESPACE_NAME} not found. Creating it..."
    kubectl create namespace "${NAMESPACE_NAME}"
fi
 
# Define the namespace directory path
namespace_dir="./${NAMESPACE_NAME}"
# Ensure the customer-specific directory exists
mkdir -p "${namespace_dir}"

create_pv() {
    local name="$1"
    local pv_name="${name}-volume-${NAMESPACE_NAME}"
    local pv_file="${namespace_dir}/${pv_name}.yaml"
 
    cat <<EOF >"${pv_file}"
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${pv_name}
  labels:
    type: local
    volume: ${name}-${NAMESPACE_NAME}
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
    local pvc_name="${name}-${NAMESPACE_NAME}"
    local pvc_file="${namespace_dir}/${pvc_name}.yaml"
 
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
  selector:
    matchLabels:
      volume: ${name}-${NAMESPACE_NAME}
EOF
}

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
 
# Function to create a DaemonSet to ensure host paths on all nodes
create_daemonset_to_ensure_hostpaths() {
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ensure-hostpaths
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: ensure-hostpaths
  template:
    metadata:
      labels:
        name: ensure-hostpaths
    spec:
      containers:
      - name: ensure-hostpaths
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            set -xe
            for name in ${names[@]}; do
              mkdir -p /host/mnt/data/${NAMESPACE_NAME}/$name && chmod -R 777 /host/mnt/data/${NAMESPACE_NAME}/$name;
            done
        volumeMounts:
        - name: host-root
          mountPath: /host
          readOnly: false
      volumes:
      - name: host-root
        hostPath:
          path: /
EOF
}

# Create PV and PVC files for each name
for name in "${names[@]}"; do
    create_pv "$name"
    create_pvc "$name"
done
 

# Define the list of additional Kubernetes YAML files to process
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
 
# Function to add namespace to Kubernetes YAML files using yq
add_namespace_with_yq() {
    echo "Adding namespaces to Kubernetes YAML files..."
    for file in "${FILES[@]}"; do
        local file_path="${file}"
        if [ -f "$file_path" ]; then
            echo "Processing file: $file_path"
            local target_file="${namespace_dir}/$(basename "$file_path")"
            # Copy the file to the namespace directory
            cp "$file_path" "$target_file"
            # Use yq to insert the namespace
            yq eval ".metadata.namespace = \"$NAMESPACE_NAME\"" -i "$target_file"
            echo "Namespace added to $target_file"
        else
            echo "Warning: File '$file_path' not found and will not be copied or updated."
        fi
    done
}

adjust_deployment_pvc_references() {
    echo "Adjusting PVC references in deployment files..."
    for file in "${FILES[@]}"; do
        if [[ "$file" == *"-deployment.yaml" ]]; then
            local deployment_file="${namespace_dir}/$(basename "$file")"
            echo "Processing $deployment_file for PVC name adjustments..."
            if [ -f "$deployment_file" ]; then
                # Append the namespace to the claimName of all persistent volume claims
                yq eval '.spec.template.spec.volumes[].persistentVolumeClaim.claimName |= sub("$"; "-'${NAMESPACE_NAME}'")' -i "$deployment_file"
                echo "Updated PVC references in $deployment_file to include -${NAMESPACE_NAME}"
            else
                echo "Deployment file $deployment_file not found."
            fi
        fi
    done
}

# Adjust proxy deployment for correct secret mounting
adjust_proxy_deployment() {
    local proxy_deployment_file="${namespace_dir}/proxy-deployment.yaml"
    if [ -f "$proxy_deployment_file" ]; then
        echo "Adjusting proxy deployment for correct secret mounting..."
        yq eval '
            .spec.template.spec.containers[0].volumeMounts[0].subPath = "cert.crt" |
            .spec.template.spec.containers[0].volumeMounts[0].mountPath = "/etc/nginx/certs/cert.crt" |
            .spec.template.spec.containers[0].volumeMounts[1].subPath = "cert.key" |
            .spec.template.spec.containers[0].volumeMounts[1].mountPath = "/etc/nginx/certs/cert.key"
        ' -i "$proxy_deployment_file"
    else
        echo "Proxy deployment file not found, skipping adjustment."
    fi
}

# Apply namespace adjustments to all specified Kubernetes YAML files
add_namespace_with_yq

# Adjust PVC references in all deployment files before applying configurations
adjust_deployment_pvc_references

# Adjust the proxy deployment
adjust_proxy_deployment

# Apply the function to create the Network Policy
create_network_policy
 
# Deploy the DaemonSet to ensure host paths are available across all nodes
create_daemonset_to_ensure_hostpaths

# Applying all generated Kubernetes YAML configurations within the namespace directory
echo "Applying all Kubernetes configurations within the $namespace_dir directory..."
kubectl apply -f "$namespace_dir/"
if [ $? -eq 0 ]; then
    echo "Successfully applied Kubernetes configurations."
else
    echo "Failed to apply some or all Kubernetes configurations."
    exit 1
fi

echo "Script execution completed."
