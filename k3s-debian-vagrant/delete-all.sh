#!/usr/bin/env bash

kubectl --kubeconfig shared/k3s.yaml delete -f nginx-ldap/nginx-k3s.yml
kubectl --kubeconfig shared/k3s.yaml get configmap | awk '{print $1}' | tail -n +2 | xargs -r -l kubectl --kubeconfig shared/k3s.yaml delete configmap