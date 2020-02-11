#!/bin/bash

declare -A ARG_ARRAY
ARG_NAME=

TMPDIR=$(mktemp -d)

while test $# -gt 0
do
    case "$1" in
        --redis-password) ARG_NAME="REDIS_PASSWORD"
            ;;
        --redis-server) ARG_NAME="REDIS_SERVER"
            ;;
        --redis-port) ARG_NAME="REDIS_PORT"
            ;;
        --redis-ssl-port) ARG_NAME="REDIS_SSL_PORT"
            ;;
        --cluster-enabled) ARG_NAME="CLUSTER_ENABLED"
            ;;
        --cluster-config-file) ARG_NAME="CLUSTER_CONFIG_FILE"
            ;;
        --cluster-node-timeout) ARG_NAME="CLUSTER_NODE_TIMEOUT"
            ;;
        --append-only) ARG_NAME="APPEND_ONLY"
            ;;
        --*) echo "Bad option $1"
            ;;

        *) ARG_ARRAY[${ARG_NAME}]=$1 && ARG_NAME=""
            ;;
    esac
    shift
done

# The /run path (linking /var/run) will be shared among local and container filesystems
REDIS_RUNDIR="/var/run"
REDIS_PID_FILE=${REDIS_RUNDIR}/redis.pid

# Define REDIS SSL variables in order to reference SSL/CA paths locally and within docker container
REDIS_SSL_CA_CERT=${REDIS_RUNDIR}/redis_ca.crt
REDIS_SSL_CA_KEY=${REDIS_RUNDIR}/redis_ca.key
REDIS_SSL_CERT=${REDIS_RUNDIR}/redis.crt
REDIS_SSL_KEY=${REDIS_RUNDIR}/redis.key

REDIS_PASSWORD=${ARG_ARRAY["REDIS_PASSWORD"]-fywdg06t63qrr1e7}
REDIS_SERVER=${ARG_ARRAY["REDIS_SERVER"]-redis-server}
REDIS_PORT=${ARG_ARRAY["REDIS_PORT"]-56379}
REDIS_SSL_PORT=${ARG_ARRAY["REDIS_SSL_PORT"]-56443}
CLUSTER_ENABLED=${ARG_ARRAY["CLUSTER_ENABLED"]-yes}
CLUSTER_CONFIG_FILE=${ARG_ARRAY["CLUSTER_CONFIG_FILE"]-nodes.conf}
CLUSTER_NODE_TIMEOUT=${ARG_ARRAY["CLUSTER_NODE_TIMEOUT"]-5000}
APPEND_ONLY=${ARG_ARRAY["APPEND_ONLY"]-yes}

if [ "${APPEND_ONLY,,}" = "yes" ] || [ "$APPEND_ONLY" = "1" ] ; then
  APPEND_ONLY="yes"
else
  APPEND_ONLY="no"
fi

if [ "${CLUSTER_ENABLED,,}" = "yes" ] || [ "$CLUSTER_ENABLED" = "1" ] ; then
  CLUSTER_ENABLED="yes"
else
  CLUSTER_ENABLED="no"
fi

# Preventive check to ensure the openssl tool is available on local system
if ! [ -x "$(command -v openssl)" ]; then
  echo 'Error: openssl is not installed.' >&2
  exit 1
fi

# Run openssl tool to accomplish the certificates shared through docker config objects
openssl genrsa -out ${REDIS_RUNDIR}/redis_ca.key 4096
openssl req \
  -x509 -new -nodes -sha256 \
  -key ${REDIS_SSL_CA_KEY} \
  -days 3650 \
  -subj '/CN=Redis Alifa CA' \
  -out ${REDIS_SSL_CA_CERT}
openssl genrsa -out ${REDIS_SSL_KEY} 2048
openssl req \
  -new -sha256 \
  -key ${REDIS_SSL_KEY} \
  -subj '/CN=Redis Alifa Cert' | \
   openssl x509 \
     -req -sha256 \
     -CA ${REDIS_SSL_CA_CERT} \
     -CAkey ${REDIS_SSL_CA_KEY} \
     -CAserial ${REDIS_RUNDIR}/redis_ca.txt \
     -CAcreateserial \
     -days 365 \
     -out ${REDIS_SSL_CERT}

REDIS_ARGS="--ssl-host 127.0.0.1 --ssl-port ${REDIS_SSL_PORT} --ssl-ca-cert ${REDIS_SSL_CA_CERT} --ssl-cert ${REDIS_SSL_CERT} --ssl-key ${REDIS_SSL_KEY}"

REDIS_CONF_FILE="${REDIS_RUN_DIR}/redis.conf"

rm -rf ${REDIS_CONF_FILE} || true

sudo tee -a ${REDIS_CONF_FILE} > /dev/null <<EOT
requirepass ${REDIS_PASSWORD}
pidfile ${REDIS_PID_FILE}
port ${REDIS_PORT}
cluster-enabled ${CLUSTER_ENABLED}
cluster-config-file ${CLUSTER_CONFIG_FILE}
cluster-node-timeout ${CLUSTER_NODE_TIMEOUT}
appendonly ${APPEND_ONLY}
tls-port ${REDIS_SSL_PORT}
tls-ca-cert-file ${REDIS_SSL_CA_CERT}
tls-cert-file ${REDIS_SSL_CERT}
tls-key-file ${REDIS_SSL_KEY}
EOT

if [ "$(docker service inspect --format "{{.Spec.Name}}" redis 2>&-)" != "redis" ]; then
  docker config ls > $TMPDIR/docker-configs # initialize configurations temporary file

  if [ "$(grep -c "redis-ssl-ca-cert" $TMPDIR/docker-configs)" -gt 0 ]; then
    docker config rm redis-ssl-ca-cert
  fi
  docker config create redis-ssl-ca-cert $REDIS_SSL_CA_CERT

  if [ "$(grep -c "redis-ssl-ca-key" $TMPDIR/docker-configs)" -gt 0 ]; then
    docker config rm redis-ssl-ca-key
  fi
  docker config create redis-ssl-ca-key $REDIS_SSL_CA_KEY

  if [ "$(grep -c "redis-ssl-cert" $TMPDIR/docker-configs)" -gt 0 ]; then
    docker config rm redis-ssl-cert
  fi
  docker config create redis-ssl-cert $REDIS_SSL_CERT

  if [ "$(grep -c "redis-ssl-key" $TMPDIR/docker-configs)" -gt 0 ]; then
    docker config rm redis-ssl-key
  fi
  docker config create redis-ssl-key $REDIS_SSL_KEY

  if [ "$(grep -c "redis-conf" $TMPDIR/docker-configs)" -gt 0 ]; then
    docker config rm redis-conf
  fi
  docker config create redis-conf $REDIS_CONF_FILE

  docker service create --name redis \
    --replicas=2 \
    --config src=redis-conf,target=/home/redis/redis.conf \
    --config src=redis-ssl-ca-cert,target=${REDIS_SSL_CA_CERT} \
    --config src=redis-ssl-ca-key,target=${REDIS_SSL_CA_KEY} \
    --config src=redis-ssl-cert,target=${REDIS_SSL_CERT} \
    --config src=redis-ssl-key,target=${REDIS_SSL_KEY} \
    --env REDIS_CONFIG_FILE="/home/redis/redis.conf" \
    --publish ${REDIS_SSL_PORT}:${REDIS_SSL_PORT} \
    --publish ${REDIS_PORT}:${REDIS_PORT} \
    redis:5.0.7-alpine 

  sleep 2

  docker service update redis --args '/home/redis/redis.conf'
else
  echo -e "\nThe \"redis\" Docker service already exists (deployment will be aborted)"
fi

echo -e "\nRedis Server service is listening on 127.0.0.1:$(grep -i 'port' $REDIS_CONF_FILE | tr '[a-z]+' ' ' | tr '\n' ' ' | tr -d '[:space:]')"

echo -e "\nThe suggested next step is to get (node.js) redis-cli written by Lu Jiajing from the official repository (https://github.com/lujiajing1126/redis-cli)\n"

