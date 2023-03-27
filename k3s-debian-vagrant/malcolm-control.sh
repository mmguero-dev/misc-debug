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
ENV_CONFIG_PATH=config
SHUTDOWN_ONLY=
while getopts 'vkm:e:' OPTION; do
  case "$OPTION" in
    v)
      VERBOSE_FLAG="-v"
      set -x
      ;;

    k)
      SHUTDOWN_ONLY=yes
      ;;

    m)
      MALCOLM_PATH="$($REALPATH -e "${OPTARG}" 2>/dev/null)"
      ;;

    e)
      ENV_CONFIG_PATH="${OPTARG}"
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
for MANIFEST in "${MALCOLM_PATH}"/kubernetes/*.yml; do
  "${KUBECTL_CMD[@]}" delete -f "${MANIFEST}" 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
done
"${KUBECTL_CMD[@]}" get configmap --namespace "${K8S_NAMESPACE}" 2>/dev/null \
    | awk '{print $1}' | tail -n +2 | grep -v "kube-root-ca\.crt" \
    | xargs -r -l "${KUBECTL_CMD[@]}" delete configmap 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
"${KUBECTL_CMD[@]}" delete namespace "${K8S_NAMESPACE}" 2>&1 | grep -Piv "${NOT_FOUND_REGEX}"
set -e

if [[ -z "${SHUTDOWN_ONLY}" ]]; then
  "${KUBECTL_CMD[@]}" create namespace "${K8S_NAMESPACE}"

  # nginx configmap files (some shared with other containers)
  "${KUBECTL_CMD[@]}" create configmap etc-nginx \
      --from-file "${MALCOLM_PATH}"/nginx/nginx_ldap.conf \
      --from-file "${MALCOLM_PATH}"/nginx/nginx.conf \
      --from-file "${MALCOLM_PATH}"/nginx/htpasswd \
      --namespace "${K8S_NAMESPACE}"
  "${KUBECTL_CMD[@]}" create configmap var-local-catrust \
      --from-file "${MALCOLM_PATH}"/nginx/ca-trust \
      --namespace "${K8S_NAMESPACE}"
  "${KUBECTL_CMD[@]}" create configmap etc-nginx-certs \
      --from-file "${MALCOLM_PATH}"/nginx/certs \
      --namespace "${K8S_NAMESPACE}"
  "${KUBECTL_CMD[@]}" create configmap etc-nginx-certs-pem \
      --from-file "${MALCOLM_PATH}"/nginx/certs/dhparam.pem \
      --namespace "${K8S_NAMESPACE}"

  # opensearch configmap files (some shared with other containers)
  "${KUBECTL_CMD[@]}" create configmap opensearch-curlrc \
      --from-file "${MALCOLM_PATH}"/.opensearch.primary.curlrc \
      --from-file "${MALCOLM_PATH}"/.opensearch.secondary.curlrc \
      --namespace "${K8S_NAMESPACE}"
  # todo: this still has to be generated locally (during auth_setup?)
  "${KUBECTL_CMD[@]}" create configmap opensearch-keystore \
      --from-file "${MALCOLM_PATH}"/opensearch/opensearch.keystore \
      --namespace "${K8S_NAMESPACE}"

  # logstash configmap files
  "${KUBECTL_CMD[@]}" create configmap logstash-certs \
      --from-file "${MALCOLM_PATH}"/logstash/certs \
      --namespace "${K8S_NAMESPACE}"
  "${KUBECTL_CMD[@]}" create configmap logstash-maps \
      --from-file "${MALCOLM_PATH}"/logstash/maps \
      --namespace "${K8S_NAMESPACE}"

  # file-monitor configmap files
  "${KUBECTL_CMD[@]}" create configmap yara-rules \
      --from-file "${MALCOLM_PATH}"/yara/rules \
      --namespace "${K8S_NAMESPACE}"

  # filebeat configmap files
  "${KUBECTL_CMD[@]}" create configmap filebeat-certs \
      --from-file "${MALCOLM_PATH}"/filebeat/certs \
      --namespace "${K8S_NAMESPACE}"

  # netbox configmap files
  "${KUBECTL_CMD[@]}" create configmap netbox-netmap-json \
      --from-file "${MALCOLM_PATH}"/net-map.json \
      --namespace "${K8S_NAMESPACE}"

  # configmap env files (try .env first, then fall back to .env.example)
  for ENV_EXAMPLE_FILE in ~/devel/github/mmguero-dev/Malcolm/"${ENV_CONFIG_PATH}"/*.env.example; do
    # strip .example
    ENV_FILE="${ENV_EXAMPLE_FILE%.*}"
    # build configname (e.g., pcap-capture.env -> pcap-capture-env )
    CONFIG_NAME="$(basename "${ENV_FILE%.*}")-env"
    if [[ -f "${ENV_FILE}" ]]; then
      # prefer local .env file
      FROM_ENV_FILE="${ENV_FILE}"
    else
      # fall back to .env.example default
      FROM_ENV_FILE="${ENV_EXAMPLE_FILE}"
    fi
    # create configmap from-env-file
    "${KUBECTL_CMD[@]}" create configmap "${CONFIG_NAME}" \
      --from-env-file "${FROM_ENV_FILE}" \
      --namespace "${K8S_NAMESPACE}"
  done

  set +e
  for MANIFEST in "${MALCOLM_PATH}"/kubernetes/*.yml; do
    "${KUBECTL_CMD[@]}" apply -f "${MANIFEST}" 2>&1
  done
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
      "${STERN_CMD[@]}" --namespace "${K8S_NAMESPACE}" '.*'
  fi

fi
