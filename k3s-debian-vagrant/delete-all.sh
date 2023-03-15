#!/usr/bin/env bash

K3S_CFG=shared/k3s.yaml
K8S_NAMESPACE=nginx-ldap
GET_OPTIONS=(-o wide)
KUBECTL_CMD=(kubectl --kubeconfig "${K3S_CFG}")

"${KUBECTL_CMD[@]}" delete -f nginx-ldap/nginx-k3s.yml
"${KUBECTL_CMD[@]}" get configmap --namespace "${K8S_NAMESPACE}" | awk '{print $1}' | tail -n +2 | grep -v "kube-root-ca\.crt" | xargs -r -l "${KUBECTL_CMD[@]}" delete configmap
"${KUBECTL_CMD[@]}" delete namespace "${K8S_NAMESPACE}"