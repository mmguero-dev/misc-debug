#!/usr/bin/env bash

kubectl --kubeconfig shared/k3s.yaml delete -f nginx-ldap/nginx-k3s.yml
kubectl --kubeconfig shared/k3s.yaml get configmap --namespace nginx-ldap | awk '{print $1}' | tail -n +2 | grep -v "kube-root-ca\.crt" | xargs -r -l kubectl --kubeconfig shared/k3s.yaml delete configmap
kubectl --kubeconfig shared/k3s.yaml delete namespace nginx-ldap
kubectl --kubeconfig shared/k3s.yaml create namespace nginx-ldap
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx --from-file nginx-ldap/nginx --namespace nginx-ldap
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx-catrust --from-file nginx-ldap/nginx/ca-trust --namespace nginx-ldap
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx-certs --from-file nginx-ldap/nginx/certs --namespace nginx-ldap
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx-certs-pem --from-file nginx-ldap/nginx/certs/dhparam.pem --namespace nginx-ldap
kubectl --kubeconfig shared/k3s.yaml apply -f nginx-ldap/nginx-k3s.yml
sleep 5
echo '--- nodes ---------------------------------------------------------------'
kubectl --kubeconfig shared/k3s.yaml -o wide get nodes
echo '--- ingresses -----------------------------------------------------------'
kubectl --kubeconfig shared/k3s.yaml -o wide get ingress --namespace nginx-ldap
echo '--- services ------------------------------------------------------------'
kubectl --kubeconfig shared/k3s.yaml -o wide get service --namespace nginx-ldap
echo '--- pods ----------------------------------------------------------------'
kubectl --kubeconfig shared/k3s.yaml -o wide get pods --namespace nginx-ldap
echo '--- configmaps ----------------------------------------------------------'
kubectl --kubeconfig shared/k3s.yaml -o wide get configmap --namespace nginx-ldap
echo '-------------------------------------------------------------------------'