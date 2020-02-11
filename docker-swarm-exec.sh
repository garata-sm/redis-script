#!/bin/bash

SERVICE_NAME="redis"

FILE_NAME=$1

TASK_ID="$(docker service ps -q ${SERVICE_NAME})"
CONT_ID="$(docker inspect -f "{{.Status.ContainerStatus.ContainerID}}" ${TASK_ID})"
NODE_ID="$(docker inspect -f "{{.NodeID}}" ${TASK_ID})"
NODE_IP="$(docker inspect -f {{.Status.Addr}} ${NODE_ID})"

_SP=$SP

SP=" "

_CONT_ID=($CONT_ID)
_NODE_IP=($NODE_IP)
_NODE_ID=($NODE_ID)

SP=$_SP

count=${#_NODE_IP[@]}

echo $count

ssh -T ${_NODE_IP[0]} << EOSSH
#docker exec ${_CONT_ID[0]} sh -c "cat /usr/local/bin/docker-entrypoint.sh"
docker exec ${_CONT_ID[0]} sh -c "netstat -tulpn | grep LISTEN"
#docker exec ${_CONT_ID[0]} sh -c "cat /usr/local/etc/redis/*"
EOSSH

