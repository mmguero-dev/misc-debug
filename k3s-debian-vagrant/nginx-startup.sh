#!/usr/bin/env bash

K3S_CFG=shared/k3s.yaml
K8S_NAMESPACE=nginx-ldap
GET_OPTIONS=(-o wide)
KUBECTL_CMD=(kubectl --kubeconfig "${K3S_CFG}")

"${KUBECTL_CMD[@]}" delete -f nginx-ldap/nginx-k3s.yml
"${KUBECTL_CMD[@]}" get configmap --namespace "${K8S_NAMESPACE}" | awk '{print $1}' | tail -n +2 | grep -v "kube-root-ca\.crt" | xargs -r -l "${KUBECTL_CMD[@]}" delete configmap
"${KUBECTL_CMD[@]}" delete namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create configmap etc-nginx --from-file nginx-ldap/nginx --namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create configmap etc-nginx-catrust --from-file nginx-ldap/nginx/ca-trust --namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create configmap etc-nginx-certs --from-file nginx-ldap/nginx/certs --namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create configmap etc-nginx-certs-pem --from-file nginx-ldap/nginx/certs/dhparam.pem --namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" apply -f nginx-ldap/nginx-k3s.yml
sleep 5
for ITEM in \
    nodes \
    ingresses \
    services \
    deployments \
    replicasets \
    pods \
    configmaps \
    persistentvolumes \
    persistentvolumeclaims \
    volumeattachments;
do
    echo "------ ${ITEM}"
    "${KUBECTL_CMD[@]}" "${GET_OPTIONS[@]}" get "${ITEM}" --namespace "${K8S_NAMESPACE}" 2>&1 | grep -v "No resources"
done
echo
