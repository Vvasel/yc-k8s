#!/bin/bash
set -e

CLUSTER_NAME=${1:-k8s-single}
NODEGROUP_NAME=${2:-k8s-demo-ng}

echo "Проверка node-group (без ошибок)..."
# Тихая проверка БЕЗ вывода ошибок
if yc managed-kubernetes node-group list --cluster-name "$CLUSTER_NAME" --format json 2>/dev/null | jq -e '.[] | select(.name=="'"$NODEGROUP_NAME"'")' > /dev/null 2>&1; then
  echo "Удаление node-group $NODEGROUP_NAME..."
  yc managed-kubernetes node-group delete --name "$NODEGROUP_NAME" --cluster-name "$CLUSTER_NAME"
else
  echo "Node-group не найдена, пропускаем."
fi

echo "Удаление кластера $CLUSTER_NAME..."
yc managed-kubernetes cluster delete --name "$CLUSTER_NAME"

#sleep 20
kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true

echo "Полная очистка завершена!"
