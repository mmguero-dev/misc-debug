#!/usr/bin/env bash

K3S_CFG=shared/k3s.yaml
K8S_NAMESPACE=nginx-ldap
GET_OPTIONS=(-o wide)
KUBECTL_CMD=(kubectl --kubeconfig "${K3S_CFG}")
NOT_FOUND_REGEX="(No resources|not) found"

"${KUBECTL_CMD[@]}" delete -f nginx-ldap/nginx-k3s.yml 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
"${KUBECTL_CMD[@]}" get configmap --namespace "${K8S_NAMESPACE}" 2>/dev/null | awk '{print $1}' | tail -n +2 | grep -v "kube-root-ca\.crt" | xargs -r -l "${KUBECTL_CMD[@]}" delete configmap 2>&1 | grep -Piv "not found"
"${KUBECTL_CMD[@]}" delete namespace "${K8S_NAMESPACE}" 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"