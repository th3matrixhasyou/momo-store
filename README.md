# Momo Store — Пельменная №2

<img width="900" alt="Momo Store" src="https://user-images.githubusercontent.com/9394918/167876466-2c530828-d658-4efe-9064-825626cc6db5.png">

## О проекте

Momo Store — веб-приложение интернет-магазина пельменей. Проект состоит из frontend на Vue.js и backend на Go. Для сборки, публикации и развертывания приложения используется GitLab CI/CD, Docker-образы хранятся в Yandex Container Registry, а приложение работает в Managed Service for Kubernetes в Yandex Cloud.

## Локальный запуск и тестирование

Для запуска приложения локально требуются Node.js/npm и Go. Команды выполняются из корня репозитория в отдельных терминалах.

Запуск frontend:

```bash
cd frontend
npm install
NODE_ENV=production VUE_APP_API_URL=http://localhost:8081 npm run serve
```

Запуск backend и выполнение тестов:

```bash
cd backend
go run ./cmd/api
go test -v ./...
```

## Архитектура решения

Инфраструктура развертывается в Yandex Cloud с использованием Infrastructure as Code (Terraform).

| Компонент | Назначение |
|---|---|
| VPC и подсеть `momo-subnet-a` | Изолированная сетевая инфраструктура в зоне `ru-central1-d` |
| Managed Service for Kubernetes | Кластер Kubernetes версии 1.35 для запуска frontend и backend |
| Группа узлов Kubernetes | Прерываемые ВМ `standard-v2`: 2 vCPU, 4 GB RAM, сетевой HDD 32 GB |
| Yandex Container Registry `momo-registry` | Хранение Docker-образов `momo-backend` и `momo-frontend` с тегами коммитов и версий |
| S3-бакет `momo-store-statics-neo` | Удаленное хранение Terraform state и статических файлов frontend |
| GitLab CI/CD | Автоматизация сборки, тестирования, публикации образов и Helm-деплоя |
| Prometheus и Grafana | Сбор и визуализация метрик backend на отдельной виртуальной машине |

Frontend публикуется через Kubernetes Service типа `LoadBalancer`. Nginx во frontend-контейнере проксирует запросы API к backend. Backend предоставляет endpoint `/health` для проверки состояния приложения и `/metrics` для выдачи метрик Prometheus. Для сбора метрик Prometheus обращается к NodePort backend-сервиса на рабочей ноде Kubernetes.

Общая последовательность доставки приложения:

1. Разработчик создает feature-ветку и отправляет изменения в GitLab.
2. GitLab CI собирает Docker-образы и выполняет тесты backend.
3. Этап release назначает образам версионные теги SemVer.
4. Этап deploy устанавливает или обновляет Helm-релизы в Kubernetes.
5. Prometheus собирает метрики backend, Grafana отображает их на dashboard.

## Стратегия ветвления и версионирования

### Ветвление

Используется **GitHub Flow**:

- `main` — основная стабильная ветка, содержащая готовый к развертыванию код.
- `feature/*` — короткоживущие ветки для разработки и изменений инфраструктуры, приложения и CI/CD.
- Изменения попадают в `main` через Merge Request после проверки и успешного выполнения необходимых этапов CI.

### Версионирование

Для версий приложения используется **Semantic Versioning (SemVer)** в формате `MAJOR.MINOR.PATCH`, например `1.0.15`.

В GitLab CI версия формируется автоматически: `1.0.${CI_PIPELINE_IID}`. `CI_PIPELINE_IID` — уникальный последовательный номер pipeline в рамках проекта, который используется как PATCH-номер версии. На этапе build образы первоначально публикуются с тегом `${CI_COMMIT_SHA}`. На этапе release утилита `crane` назначает этим же образам SemVer-тег и тег `latest`. На этапе deploy Helm устанавливает образы с SemVer-тегом текущего pipeline.

Таким образом, для одного и того же исходного коммита сохраняется тег по SHA, а для релиза дополнительно создается версионный тег.

## Предварительные требования

Для развертывания потребуются:

1. Аккаунт и каталог в Yandex Cloud с необходимыми квотами.
2. Установленный и настроенный `yc CLI`.
3. Terraform, `kubectl` и Helm на рабочей машине.
4. Сервисный аккаунт Yandex Cloud с правами, необходимыми Terraform для создания инфраструктуры и CI для публикации образов. Для Terraform подготовьте IAM-ключ в формате JSON (`key.json`).
5. S3-бакет и статические ключи доступа для удаленного Terraform state.
6. GitLab-проект с доступным GitLab Runner и настроенными CI/CD Variables.

Перед созданием кластера проверьте квоты Yandex Cloud в зоне `ru-central1-d`, в частности доступный объем дисков. Для конфигурации проекта предусмотрите не менее 50 GB дисковой квоты.

## 1. Развертывание инфраструктуры (Terraform)

### 1.1. Подготовка доступа

Установите `yc CLI`, авторизуйтесь и выберите нужный каталог Yandex Cloud. Для Terraform подготовьте JSON-ключ сервисного аккаунта и разместите его в каталоге `terraform/` под именем `key.json`.

Файлы с ключами и параметрами доступа не должны попадать в Git. В частности, `terraform/key.json` и `terraform/backend.conf` должны быть исключены через `.gitignore`.

### 1.2. Настройка удаленного состояния

Перейдите в каталог Terraform:

```bash
cd terraform
```

Создайте `backend.conf` с параметрами доступа к S3-бакету. Значения ниже замените собственными:

```ini
access_key = "<S3_ACCESS_KEY>"
secret_key = "<S3_SECRET_KEY>"
```

Параметры endpoint, bucket и key задаются в конфигурации Terraform backend проекта. `backend.conf` содержит секреты и не должен коммититься.

Инициализируйте Terraform:

```bash
terraform init -backend-config=backend.conf
```

Проверьте план:

```bash
terraform plan
```

Создайте инфраструктуру:

```bash
terraform apply
```

Проверьте итоговые ресурсы в консоли Yandex Cloud и сохраните выведенные Terraform значения, которые понадобятся для подключения к кластеру и настройки мониторинга.

## 2. Подключение к Kubernetes

Получите учетные данные созданного кластера:

```bash
yc managed-kubernetes cluster get-credentials --name momo-cluster --external --force
```

Проверьте подключение и состояние узлов:

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

Узлы кластера должны перейти в состояние `Ready`. В выводе `kubectl get nodes -o wide` можно посмотреть адреса узлов; публичный адрес рабочей ноды понадобится для настройки Prometheus.

## 3. Настройка GitLab CI/CD

### 3.1. Переменные GitLab

Откройте GitLab-проект и перейдите в **Settings → CI/CD → Variables**. Добавьте переменные, используемые pipeline:

| Переменная | Значение |
|---|---|
| `YC_SA_JSON` | Содержимое JSON-ключа сервисного аккаунта Yandex Cloud, используемого для публикации образов |
| `YC_REGISTRY_ID` | ID каталога Container Registry, в котором находятся `momo-backend` и `momo-frontend` |
| `KUBE_CONFIG` | Base64-представление kubeconfig для подключения GitLab Runner к Kubernetes |

Переменные должны быть доступны тем pipeline, которым разрешено выполнять соответствующие операции. Для защищенного production-деплоя рекомендуется ограничить deploy-этап основной веткой `main`, а секретные переменные сделать Protected. Настройки доступности переменных должны соответствовать правилам запуска pipeline в `.gitlab-ci.yml`.

Не добавляйте JSON-ключи, токены, kubeconfig, `backend.conf` или Terraform state в репозиторий. Base64 не шифрует содержимое: значение `KUBE_CONFIG` остается секретом и должно храниться только в GitLab CI/CD Variables.

### 3.2. Подготовка ServiceAccount для деплоя

На машине, с которой доступен кластер через `kubectl`, создайте ServiceAccount:

```bash
kubectl create serviceaccount gitlab-deployer -n default --dry-run=client -o yaml | kubectl apply -f -
```

Для текущей учебной конфигурации ServiceAccount привязывается к `cluster-admin`:

```bash
kubectl create clusterrolebinding gitlab-deployer-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=default:gitlab-deployer \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Замечание по безопасности:** `cluster-admin` предоставляет полные административные права на весь кластер. Это упрощенный вариант для учебного стенда, а не рекомендуемая настройка production. Для рабочего окружения следует выдать ServiceAccount только необходимые права в namespace, где выполняется Helm-деплой.

Сформируйте kubeconfig для GitLab. Команда использует адрес API-сервера текущего Kubernetes-контекста и создает токен ServiceAccount:

```bash
APISERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
TOKEN="$(kubectl create token gitlab-deployer --duration=8760h)"

cat <<KUBECONFIG_EOF | base64 -w 0
apiVersion: v1
kind: Config
clusters:
- name: momo-cluster
  cluster:
    insecure-skip-tls-verify: true
    server: ${APISERVER}
users:
- name: gitlab-deployer
  user:
    token: ${TOKEN}
contexts:
- name: momo-context
  context:
    cluster: momo-cluster
    user: gitlab-deployer
current-context: momo-context
KUBECONFIG_EOF

echo
unset TOKEN
```

Скопируйте полученную Base64-строку целиком и сохраните ее в GitLab CI/CD Variables под ключом `KUBE_CONFIG`. Не вставляйте сам токен или Base64-строку в README, коммиты или сообщения.

В приведенной конфигурации отключена проверка TLS-сертификата API-сервера (`insecure-skip-tls-verify: true`). Для более безопасной конфигурации следует использовать CA-сертификат кластера. Также учитывайте, что фактический срок действия токена может ограничиваться настройками Kubernetes API server, даже если в команде запрошено `8760h`.

### 3.3. Работа pipeline

В корне репозитория находится `.gitlab-ci.yml` с четырьмя этапами:

| Этап | Назначение |
|---|---|
| `build` | Сборка Docker-образов frontend и backend и публикация в Yandex Container Registry с тегом `${CI_COMMIT_SHA}` |
| `test` | Запуск тестов backend командой `go test -v ./...` |
| `release` | Назначение образам тегов `1.0.${CI_PIPELINE_IID}` и `latest` с помощью `crane` |
| `deploy` | Обновление Helm-релизов `momo-backend` и `momo-frontend` в Kubernetes с использованием версии текущего pipeline |

Чтобы запустить pipeline, отправьте изменения в GitLab:

```bash
git add .
git commit -m "feat: configure CI/CD and Kubernetes deployment"
git push origin <имя-ветки>
```

Откройте в GitLab раздел **Build → Pipelines** и проверьте результат выполнения jobs. Успешное выполнение `deploy` означает, что Helm-команды завершились без ошибки и дождались готовности ресурсов согласно параметру `--wait`.

## 4. Настройка Helm и развертывание приложения

Приложение упаковано в два Helm-чарта:

- `helm/momo-store-backend` — backend;
- `helm/momo-store-frontend` — frontend.

В `values.yaml` каждого чарта задаются репозиторий образа, тег по умолчанию, количество реплик и ресурсы контейнера. Для обоих компонентов настроены следующие ресурсы:

```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "100m"
  limits:
    memory: "128Mi"
    cpu: "200m"
```

Для backend настроены `livenessProbe` и `readinessProbe`, выполняющие HTTP-проверку `GET /health` на порту `8081`. Для frontend обе пробы проверяют `GET /` на порту `80`.

Проверьте шаблоны чартов перед установкой:

```bash
helm lint ./helm/momo-store-backend
helm lint ./helm/momo-store-frontend
```

При автоматическом деплое GitLab CI передает текущую версию через `--set image.tag="${VERSION}"`, поэтому вручную менять тег в `values.yaml` перед каждым pipeline не требуется.

Для ручного развертывания укажите существующий тег образов:

```bash
VERSION="<тег-образа>"

helm upgrade --install momo-backend ./helm/momo-store-backend \
  --set image.tag="${VERSION}" --wait --timeout 5m

helm upgrade --install momo-frontend ./helm/momo-store-frontend \
  --set image.tag="${VERSION}" --wait --timeout 5m
```

Проверьте состояние релизов и подов:

```bash
helm list -n default
kubectl get pods -n default -o wide
kubectl get deployments -n default
kubectl get services -n default
```

Поды frontend и backend должны перейти в состояние `Running`, а контейнеры — стать Ready. При необходимости проверьте rollout:

```bash
kubectl rollout status deployment/momo-store-backend -n default
kubectl rollout status deployment/momo-store-frontend -n default
```

## 5. Проверка приложения

Получите внешний адрес frontend Service:

```bash
kubectl get svc momo-store-frontend -n default
```

Дождитесь появления внешнего IP в столбце `EXTERNAL-IP` и откройте его в браузере. Должна загрузиться витрина магазина.

Проверьте основные API-маршруты через адрес приложения:

- `/products`
- `/categories`
- `/whoami`

Запросы API должны проходить через Nginx-прокси frontend к backend. Endpoint backend `/health` должен возвращать успешный ответ, а `/metrics` — метрики в формате Prometheus.

## 6. Мониторинг (Prometheus и Grafana)

Prometheus и Grafana размещены на отдельной виртуальной машине Ubuntu вне Kubernetes-кластера. Backend остается в Managed Service for Kubernetes, а Prometheus получает его метрики через NodePort.

### 6.1. Настройка Prometheus

На виртуальной машине мониторинга создайте каталог и файл конфигурации:

```bash
mkdir -p /home/ubuntu/monitoring
nano /home/ubuntu/monitoring/prometheus.yml
```

Пример конфигурации. Вместо `<PUBLIC_IP_OF_KUBERNETES_NODE>` укажите внешний IP рабочей ноды Kubernetes. NodePort backend в текущей конфигурации — `31046`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "momo-store-backend"
    metrics_path: /metrics
    static_configs:
      - targets: ["<PUBLIC_IP_OF_KUBERNETES_NODE>:31046"]
```

Запустите Prometheus в Docker с host networking (в этой конфигурации Prometheus использует сетевой стек хоста):

```bash
docker run -d \
  --name prometheus \
  --network host \
  -v /home/ubuntu/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:latest
```

После изменения конфигурации перезапустите контейнер:

```bash
docker restart prometheus
```

Откройте `http://<MONITORING_VM_PUBLIC_IP>:9090/targets`. У jobs `prometheus` и `momo-store-backend` ожидается состояние `UP`. Если backend target находится в состоянии `DOWN`, проверьте адрес рабочей ноды, NodePort, сетевые правила и доступность `/metrics` с виртуальной машины мониторинга.

### 6.2. Подключение Prometheus в Grafana

Откройте Grafana по адресу `http://<MONITORING_VM_PUBLIC_IP>:3000`.

1. Перейдите в **Connections → Data sources**.
2. Нажмите **Add data source** и выберите **Prometheus**.
3. В поле **Name** укажите `Prometheus`.
4. В поле **Prometheus server URL** укажите адрес Prometheus, доступный именно из контейнера Grafana. Например: `http://<PRIVATE_IP_OF_MONITORING_VM>:9090`.
5. Нажмите **Save & test**. Источник данных должен успешно подключиться.

Не указывайте `localhost:9090`, если Grafana работает в отдельном Docker-контейнере: в таком случае `localhost` указывает на сам контейнер Grafana, а не на виртуальную машину или контейнер Prometheus.

### 6.3. Dashboard и метрики

Создайте dashboard с названием `Momo Store — Monitoring` и добавьте панели для основных метрик backend. В текущем наборе метрик доступны:

| Название панели | PromQL | Назначение |
|---|---|---|
| Request Rate (RPS) | `rate(requests_count[$__rate_interval])` | Скорость поступления запросов |
| Average Response Time (ms) | `rate(response_timing_ms_sum[$__rate_interval]) / rate(response_timing_ms_count[$__rate_interval])` | Среднее время обработки запроса в миллисекундах |
| Total Requests | `requests_count` | Общее число запросов с момента запуска приложения или сброса счетчика |
| Total Orders | `orders_count` | Общее число заказов |
| Product Listings | `sum(dumplings_listing_count)` | Общее число обращений к карточкам/списку товаров по доступным меткам |
| Backend Metrics Target | `up{job="momo-store-backend"}` | Доступность target для сбора метрик Prometheus: `1` — scrape успешен, `0` — scrape неуспешен |

Для панели `Average Response Time (ms)` установите единицу измерения `milliseconds (ms)`. Для `Request Rate (RPS)` используйте запрос с `rate`, чтобы отображать скорость запросов в секунду.

**Ограничение текущей инструментализации:** в приведенном наборе `/metrics` присутствуют `requests_count`, `orders_count`, `dumplings_listing_count` и histogram `response_timing_ms`. Отдельный счетчик HTTP-ошибок в этом наборе не обнаружен. Поэтому полноценную панель Error Rate нельзя построить только на перечисленных метриках: для нее backend должен дополнительно экспортировать счетчик ошибок или HTTP-запросов с меткой кода ответа.

## 7. Исключение секретов и служебных файлов из Git

В корневом `.gitignore` должны быть исключены Terraform state, локальный каталог Terraform и секретные файлы:

```gitignore
# Terraform state and local files
*.tfstate
*.tfstate.*
*.tfplan
.terraform/

# Secrets and local credentials
terraform/key.json
terraform/backend.conf
terraform/id_ed25519*
```

Файл `.terraform.lock.hcl` рекомендуется **оставить в репозитории**: он фиксирует версии Terraform provider-плагинов и обеспечивает воспроизводимость `terraform init`.

Проверьте, не отслеживаются ли секреты Git:

```bash
git ls-files terraform.tfstate terraform/key.json terraform/backend.conf
```

Если команда вывела один из этих файлов, одного `.gitignore` недостаточно: файл уже отслеживается Git. Удалите из индекса только те файлы, которые показала предыдущая команда, например:

```bash
git rm --cached terraform.tfstate
```

Перед отправкой изменений проверьте:

```bash
git status
```

Если секреты ранее уже попадали в GitLab, добавление `.gitignore` не удаляет их из истории Git. Такие ключи и токены необходимо заменить.

## Полезные команды для диагностики

```bash
# yc
yc compute instance get momo-monitoring --format json | grep -i -A 3 'one_to_one_nat'
yc k8s node-group list
yc k8s node-group get <ID_ГРУППЫ_УЗЛОВ>


# Terraform
terraform apply -auto-approve
terraform destroy -auto-approve

# Kubernetes
kubectl get nodes -o wide
kubectl get pods -n default -o wide
kubectl get services -n default
kubectl describe pod <POD_NAME> -n default
kubectl logs <POD_NAME> -n default
kubectl get svc

# Helm
helm list -n default
helm status momo-backend -n default
helm status momo-frontend -n default

# Monitoring VM
docker ps
docker logs prometheus
docker logs grafana
```
