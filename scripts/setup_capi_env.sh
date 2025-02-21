#!/usr/bin/env bash
set -euo pipefail
set -o xtrace

export HYPERSHIFT_IMAGE="${HYPERSHIFT_IMAGE:-quay.io/hypershift/hypershift-operator:latest}"
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
export CONTAINER_COMMAND=${CONTAINER_COMMAND:-podman}
export BASE_DIR=build

function waitForPodsReadyStatus(){
  while [[ $(kubectl get pods -n $1 -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}'| tr ' ' '\n'  | sort -u) != "True" ]]; do
    echo "Waiting for pods in namespace $1 to be ready"
    kubectl get pods -n $1 -o 'jsonpath={..status.containerStatuses}' | jq "."
    sleep 5;
  done
  echo "Pods in namespace $1 are ready"
}

deploy_hypershift() {
  kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.51.1/bundle.yaml || true
  HYPERSHIFT_BIN_DIR=$BASE_DIR/hypershift/bin

  if [[ "$(${CONTAINER_COMMAND} images -q $HYPERSHIFT_IMAGE 2> /dev/null)" != "" ]]; then
    echo "Deleting old hypershift image"
    ${CONTAINER_COMMAND} rmi $HYPERSHIFT_IMAGE -f
  fi
  mkdir -p $HYPERSHIFT_BIN_DIR
  echo "Copy the binary from the image"
  # The same binary is later used by the hypershift helper class
  ${CONTAINER_COMMAND} run -it --rm\
  -v $(pwd)/$HYPERSHIFT_BIN_DIR:/root/hypershift_bin:Z \
  --entrypoint cp \
  "$HYPERSHIFT_IMAGE" \
  /usr/bin/hypershift /root/hypershift_bin

  $HYPERSHIFT_BIN_DIR/hypershift install --hypershift-image "$HYPERSHIFT_IMAGE"
  waitForPodsReadyStatus hypershift
}

echo "Deploying HyperShift"
deploy_hypershift
echo "Set worker label for minikube"
kubectl get nodes minikube && kubectl label node minikube node-role.kubernetes.io/worker="" --overwrite
