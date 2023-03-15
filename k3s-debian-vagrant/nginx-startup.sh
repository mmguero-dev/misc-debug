#!/usr/bin/env bash

kubectl --kubeconfig shared/k3s.yaml delete -f nginx-ldap/nginx-k3s.yml
kubectl --kubeconfig shared/k3s.yaml get configmap | awk '{print $1}' | tail -n +2 | xargs -r -l kubectl --kubeconfig shared/k3s.yaml delete configmap
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx --from-file nginx-ldap/nginx
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx-catrust --from-file nginx-ldap/nginx/ca-trust
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx-certs --from-file nginx-ldap/nginx/certs
kubectl --kubeconfig shared/k3s.yaml create configmap etc-nginx-certs-pem --from-file nginx-ldap/nginx/certs/dhparam.pem
kubectl --kubeconfig shared/k3s.yaml apply -f nginx-ldap/nginx-k3s.yml