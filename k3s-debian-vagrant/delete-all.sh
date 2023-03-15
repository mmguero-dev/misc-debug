#!/usr/bin/env bash

kubectl --kubeconfig shared/k3s.yaml delete -f nginx-ldap/nginx-k3s.yml
kubectl --kubeconfig shared/k3s.yaml get configmap --namespace nginx-ldap | awk '{print $1}' | tail -n +2 | grep -v "kube-root-ca\.crt" | xargs -r -l kubectl --kubeconfig shared/k3s.yaml delete configmap
kubectl --kubeconfig shared/k3s.yaml delete namespace nginx-ldap
