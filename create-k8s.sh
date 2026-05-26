#!/usr/bin/env bash
set -euxo pipefail

# Функция ожидания создания кластера
wait_for_cluster() {
  local CLUSTER_NAME="$1"
  local TIMEOUT=1800   # максимум 30 минут
  local INTERVAL=20
  local ELAPSED=0

  echo "Ожидание кластера '$CLUSTER_NAME' статуса RUNNING..."

  while true; do
    STATUS=$(yc managed-kubernetes cluster get "$CLUSTER_NAME" --format json 2>/dev/null | jq -r '.status // empty')

    if [[ "$STATUS" == "RUNNING" ]]; then
      echo "Кластер готов"
      return 0
    fi

    if [[ "$STATUS" == "ERROR" ]]; then
      echo "Ошибка создания кластера"
      return 1
    fi

    echo "Текущий статус: ${STATUS:-NOT CREATED YET}"

    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))

    if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
      echo "Таймаут создания кластера"
      return 1
    fi
  done
}

# Функция ожидания создания node-group
wait_for_node_group() {
  local CLUSTER_NAME="$1" # Оставляем для совместимости вызова
  local NODE_GROUP_NAME="$2"
  local TIMEOUT=1800
  local INTERVAL=20
  local ELAPSED=0

  echo "Ожидание группы узлов '$NODE_GROUP_NAME' в папке $FOLDER_ID..."

  while true; do
    # Ищем группу по имени во всей папке
    STATUS=$(yc managed-kubernetes node-group list --folder-id "$FOLDER_ID" --format json | \
      jq -r ".[] | select(.name == \"$NODE_GROUP_NAME\") | .status // empty")

    if [[ "$STATUS" == "RUNNING" ]]; then
      echo "Группа узлов готова (статус RUNNING)"
      return 0
    fi

    if [[ "$STATUS" == "ERROR" ]]; then
      echo "Ошибка: статус ERROR"
      return 1
    fi

    echo "Текущий статус: ${STATUS:-SEARCHING...}"

    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    [ "$ELAPSED" -ge "$TIMEOUT" ] && return 1
  done
}

# Переменные
FOLDER_ID="Вот здесь прописать свой folder id"
NETWORK="k8s-net"
SUBNET="k8s-subnet"
SUBNET_RANGE="10.10.0.0/24"
SA_RES="k8s-res-sa"
SA_NODE="k8s-node-sa"
CLUSTER="k8s-cluster"
NODE_GROUP="k8s-node-group"

# Создать сеть и получить id
if yc vpc network get "$NETWORK" >/dev/null 2>&1; then
  echo "Network already exists"
  NETWORK_ID=$(yc vpc network get "$NETWORK" --format json | jq -r '.id')
else
  echo "Creating network"
  NETWORK_ID=$(yc vpc network create \
    --name "$NETWORK" \
    --description "My k8s network" \
    --folder-id "$FOLDER_ID" \
    --format json | jq -r '.id')
fi

# Создать подсеть и получить id
if yc vpc subnet get "$SUBNET" >/dev/null 2>&1; then
  echo "Subnet already exists"
  SUBNET_ID=$(yc vpc subnet get "$SUBNET" --format json | jq -r '.id')
else
  echo "Creating subnet"
  SUBNET_ID=$(yc vpc subnet create \
    --name "$SUBNET" \
    --description "My test subnet" \
    --folder-id "$FOLDER_ID" \
    --network-id "$NETWORK_ID" \
    --zone ru-central1-a \
    --range "$SUBNET_RANGE" \
    --format json | jq -r '.id')
fi

# Создать или получить id сервисного аккаунта
if yc iam service-account get --name "$SA_RES" >/dev/null 2>&1; then
  RES_SA_ID=$(yc iam service-account get --name "$SA_RES" --format json | jq -r '.id')
else
  RES_SA_ID=$(yc iam service-account create \
    --name "$SA_RES" \
    --format json | jq -r '.id')
fi

if yc iam service-account get --name "$SA_NODE" >/dev/null 2>&1; then
  NODE_SA_ID=$(yc iam service-account get --name "$SA_NODE" --format json | jq -r .id)
else
  NODE_SA_ID=$(yc iam service-account create \
    --name "$SA_NODE" \
    --format json | jq -r '.id')
fi

# Назначить роли для сервисных аккаунтов
yc resource-manager folder add-access-binding \
  --id "$FOLDER_ID" \
  --role "k8s.clusters.agent" \
  --service-account-id "$RES_SA_ID"

yc resource-manager folder add-access-binding \
  --id "$FOLDER_ID" \
  --role "vpc.publicAdmin" \
  --service-account-id "$RES_SA_ID"

# Назначить роли для узлов (puller образов)
yc resource-manager folder add-access-binding \
  --id "$FOLDER_ID" \
  --role "container-registry.images.puller" \
  --service-account-id "$NODE_SA_ID"

# создать кластер Managed Kubernetes
if yc managed-kubernetes cluster get "$CLUSTER" >/dev/null 2>&1; then
  echo "Кластер '$CLUSTER' уже создан"
else
  echo "Создание кластера '$CLUSTER'"
  yc managed-kubernetes cluster create "$CLUSTER" \
    --network-id "$NETWORK_ID" \
    --subnet-id "$SUBNET_ID" \
    --service-account-id "$RES_SA_ID" \
    --node-service-account-id "$NODE_SA_ID" \
    --cluster-ipv4-range "10.2.0.0/16" \
    --service-ipv4-range "10.3.0.0/16" \
    --zone ru-central1-a \
    --public-ip \
    --format json
fi
# подождать пока кластер создастся
echo "Кластер создается, ожидание..."
wait_for_cluster "$CLUSTER"

set +e
NODE_GROUP_EXISTS=$(yc managed-kubernetes node-group get "$NODE_GROUP" --cluster-name "$CLUSTER" --format json 2>/dev/null | jq -r '.id // empty')

if [ -z "$NODE_GROUP_EXISTS" ]; then
  echo "Node group '$NODE_GROUP' не найдена — создаём..."
  OUTPUT=$(yc managed-kubernetes node-group create "$NODE_GROUP" \
    --cluster-name "$CLUSTER" \
    --platform-id standard-v3 \
    --cores 2 \
    --core-fraction 50 \
    --memory 2 \
    --disk-size 50GB \
    --disk-type network-ssd \
    --fixed-size 1 \
    --max-expansion 3 \
    --max-unavailable 1 \
    --location subnet-id="$SUBNET_ID",zone=ru-central1-a \
    --preemptible 2>&1)
  RC=$?
  if [ $RC -ne 0 ] && ! echo "$OUTPUT" | grep -q "AlreadyExists"; then
    echo "Ошибка создания node group:"
    echo "$OUTPUT"
    exit $RC
  fi
else
  echo "Node group '$NODE_GROUP' уже существует"
fi
set -e

echo "Node group готова"

echo "Ожидание готовности node group..."
wait_for_node_group "$CLUSTER" "$NODE_GROUP"

echo "Настраиваем kubeconfig для кластера '$CLUSTER'..."

# 1. Получаем свежие данные (теперь там будет public_v4_endpoint)
CLUSTER_DATA=$(yc managed-kubernetes cluster get "$CLUSTER" --format json)
CLUSTER_ID=$(echo "$CLUSTER_DATA" | jq -r '.id')

# 2. Получаем credentials через внешний адрес
echo "Получаем доступ к кластеру $CLUSTER_ID через внешний IP..."
yc managed-kubernetes cluster get-credentials --id "$CLUSTER_ID" --external --force

# 3. Находим контекст (ищем по ID или имени кластера)
NEW_CONTEXT=$(kubectl config get-contexts -o name | grep -E "$CLUSTER_ID|$CLUSTER" | head -n 1)

if [ -n "$NEW_CONTEXT" ]; then
  kubectl config use-context "$NEW_CONTEXT"
  echo "---"
  echo "Успех! Теперь kubectl работает через интернет."
  kubectl get nodes
else
  echo "Ошибка: Контекст не найден"
  exit 1
fi
