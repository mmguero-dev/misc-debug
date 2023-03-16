#!/usr/bin/env bash

set -e
set -u
set -o pipefail

ENCODING="utf-8"

[[ "$(uname -s)" = 'Darwin' ]] && REALPATH=grealpath || REALPATH=realpath
[[ "$(uname -s)" = 'Darwin' ]] && DIRNAME=gdirname || DIRNAME=dirname
if ! (type "$REALPATH" && type "$DIRNAME") > /dev/null; then
  echo "$(basename "${BASH_SOURCE[0]}") requires $REALPATH and $DIRNAME" >&2
  exit 1
fi
export SCRIPT_PATH="$($DIRNAME $($REALPATH -e "${BASH_SOURCE[0]}"))"

MALCOLM_PATH=
while getopts 'vm:' OPTION; do
  case "$OPTION" in
    v)
      VERBOSE_FLAG="-v"
      set -x
      ;;

    m)
      MALCOLM_PATH="$($REALPATH -e "${OPTARG}" 2>/dev/null)"
      ;;

    ?)
      echo "script usage: $(basename $0) [-v (verbose)] -m <Malcolm path>" >&2
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

K3S_CFG="${SCRIPT_PATH}"/shared/k3s.yaml
K8S_NAMESPACE=malcolm
K8S_APP=malcolm-app
GET_OPTIONS=(-o wide)
KUBECTL_CMD=(kubectl --kubeconfig "${K3S_CFG}")
STERN_CMD=(stern --kubeconfig "${K3S_CFG}")
NOT_FOUND_REGEX="(No resources|not) found"

if [[ ! -d "${MALCOLM_PATH}"/kubernetes ]]; then
  echo "\"${MALCOLM_PATH}/kubernetes\" does not exist" >&2
  exit 1
fi

# destroy previous run
set +e
"${KUBECTL_CMD[@]}" delete -f "${MALCOLM_PATH}"/kubernetes/* 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
"${KUBECTL_CMD[@]}" get configmap --namespace "${K8S_NAMESPACE}" 2>/dev/null \
    | awk '{print $1}' | tail -n +2 | grep -v "kube-root-ca\.crt" \
    | xargs -r -l "${KUBECTL_CMD[@]}" delete configmap 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
"${KUBECTL_CMD[@]}" delete namespace "${K8S_NAMESPACE}" 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
set -e

"${KUBECTL_CMD[@]}" create namespace "${K8S_NAMESPACE}"

"${KUBECTL_CMD[@]}" create configmap etc-nginx \
    --from-file "${MALCOLM_PATH}"/nginx/nginx_ldap.conf \
    --from-file "${MALCOLM_PATH}"/nginx/nginx.conf \
    --from-file "${MALCOLM_PATH}"/nginx/htpasswd \
    --namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create configmap var-local-catrust-volume \
    --from-file "${MALCOLM_PATH}"/nginx/ca-trust \
    --namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create configmap etc-nginx-certs \
    --from-file "${MALCOLM_PATH}"/nginx/certs \
    --namespace "${K8S_NAMESPACE}"
"${KUBECTL_CMD[@]}" create configmap etc-nginx-certs-pem \
    --from-file "${MALCOLM_PATH}"/nginx/certs/dhparam.pem \
    --namespace "${K8S_NAMESPACE}"

set +e
"${KUBECTL_CMD[@]}" apply -f "${MALCOLM_PATH}"/kubernetes/*
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
    "${KUBECTL_CMD[@]}" "${GET_OPTIONS[@]}" get "${ITEM}" --namespace "${K8S_NAMESPACE}" 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
done
echo

if command -v stern >/dev/null 2>&1; then
    "${STERN_CMD[@]}" --namespace "${K8S_NAMESPACE}" "${K8S_APP}"
fi
