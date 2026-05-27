# Yandex Cloud Managed Kubernetes Automator

Bash-скрипты для полностью автоматического развертывания и удаления (clean-up) отказоустойчивого кластера Managed Kubernetes в облаке **Yandex Cloud**.

## Что делает скрипт:
1. **Идемпотентность:** Проверяет наличие ресурсов перед их созданием (сеть, подсеть, сервисные аккаунты). Если они есть — использует существующие.
2. **Сетевая топология:** Создает сеть в зоне `ru-central1-a` с выделенными пулами IP для подов и сервисов.
3. **Безопасность (IAM):** Автоматически генерирует и настраивает два сервисных аккаунта с минимально необходимыми ролями (`k8s.clusters.agent`, `vpc.publicAdmin`, `container-registry.images.puller`).
4. **Оркестрация:** Разворачивает мастер-ноду Kubernetes с публичным IP-адресом и прерываемую (preemptible) Node Group для экономии бюджета.
5. **Автоматизация ожидания:** Опрашивает API Yandex Cloud через циклы с разбором JSON (`jq`) до полной готовности кластера и узлов.
6. **GitOps/Управление:** Автоматически скачивает `kubeconfig`, переключает контекст локального `kubectl` и проверяет статус нод.

## Требования
* Наличие учётной записи на Yandex Cloud и платёжный аккаунт
* Установленный и инициализированный [Yandex Cloud CLI (yc)](https://cloud.yandex.ru/docs/cli/operations/install-cli)
* Утилита [jq](https://stedolan.github.io/jq/)
* [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Использование

1. Клонируйте репозиторий и перейдите в папку:
git clone [https://github.com/Vvasel/yc-k8s.git](https://github.com/Vvasel/yc-k8s.git)
cd yc-k8s

2. Откройте скрипт и укажите ваш FOLDER_ID в переменной.

3. Для создания кластера сделайте скрипт create-k8s.sh исполняемым и запустите:

chmod +x create-k8s.sh
./create-k8s.sh

4. Для удаления кластера сделайте скрипт delete-k8s.sh исполняемым и запустите:
chmod +x delete-k8s.sh
./delete-k8s.sh
