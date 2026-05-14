# AIOps Platform — Kubernetes 部署指南（Docker Desktop）

本指南說明如何將 AIOps 平台部署到 **Docker Desktop 內建的 Kubernetes**，  
使用 Plain YAML 資源清單、NGINX Ingress Controller、所有基礎設施服務皆在 K8s 內部運行。

---

## 與 Docker Compose 的對照關係

| Docker Compose | Kubernetes |
|---|---|
| 服務名稱 DNS（如 `keycloak`） | 相同 — K8s Service 名稱即為 DNS |
| Named volumes | PersistentVolumeClaim（StorageClass: `hostpath`）|
| `depends_on` + healthcheck | Readiness Probe — Pod 重試直到依賴就緒 |
| Keycloak `localhost:8090` | Keycloak NodePort `localhost:30090` |
| 每服務 `app.env` 設定檔 | ConfigMap（非機密）+ Secret（機密）|
| `host.docker.internal`（Ollama）| 在 Docker Desktop K8s 上同樣有效 |

---

## 目錄結構

```
deploy/k8s/
├── 00-namespace.yaml
├── 01-secrets.yaml            ← 所有機密 Token（base64）
├── 02-configmaps.yaml         ← 環境變數 + init.sql 內嵌
├── infra/
│   ├── postgres.yaml          ← StatefulSet + PVC + Service
│   ├── mongo.yaml             ← StatefulSet + PVC + Service
│   ├── redis.yaml             ← Deployment + Service
│   └── keycloak.yaml          ← Deployment + PVC + NodePort:30090
├── apps/
│   ├── ontology-simulator.yaml
│   ├── java-api.yaml
│   ├── java-scheduler.yaml
| ├── python-sidecar.yaml
│   └── aiops-app.yaml
├── jobs/
│   └── postgres-init.yaml     ← 一次性 Job，執行 init.sql
└── ingress.yaml               ← NGINX Ingress，路由至 aiops-app
```

---

## 前置步驟（一次性）

### 1. 啟用 Docker Desktop Kubernetes

Docker Desktop → 設定 → Kubernetes → 勾選「Enable Kubernetes」→ Apply & Restart

等待左下角 Kubernetes 狀態變成綠色。

```powershell
kubectl get nodes
# 預期：1 個 Node，STATUS = Ready
```

### 2. 安裝 NGINX Ingress Controller

```powershell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

# 等待 controller Pod 就緒
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=120s
```

---

## 步驟一：準備映像

K8s 使用本地 Docker 映像，需要先將 docker-compose build 的映像加上標籤：

```powershell
# 先確認映像已存在（之前 docker compose build 過）
docker images | Select-String "deploy-"

# 加上 k8s 標籤
docker tag deploy-aiops-app:latest            aiops-app:k8s
docker tag deploy-aiops-java-api:latest       aiops-java-api:k8s
docker tag deploy-aiops-java-scheduler:latest aiops-java-scheduler:k8s
docker tag deploy-aiops-python-sidecar:latest aiops-python-sidecar:k8s
docker tag deploy-ontology-simulator:latest   ontology-simulator:k8s
```

> 如果映像不存在（首次部署），先執行：
> ```powershell
> docker compose -f deploy/docker-compose.yml build
> ```
> 再執行上方 tag 指令。

---

## 步驟二：修改 Secrets（可選，建議在正式環境修改）

開啟 `deploy/k8s/01-secrets.yaml`，所有值為 base64 編碼。

**如需修改某個 Token**，先產生 base64 值：
```powershell
[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("你的新值"))
```

重要提醒：以下 Token 在多個服務間必須一致（修改一個就要全部更新）：

| Token | 對應 Secret Key |
|---|---|
| PostgreSQL 密碼 | `db-password` |
| Java → Frontend 內部 Token | `java-internal-token` |
| Java/Scheduler → Sidecar Token | `sidecar-token` |
| Scheduler 內部 Token | `scheduler-token` |
| Keycloak OIDC Upsert Secret | `upsert-secret` |

---

## 步驟三：部署基礎設施

```powershell
# 建立 namespace
kubectl apply -f deploy/k8s/00-namespace.yaml

# 部署 Secrets + ConfigMaps
kubectl apply -f deploy/k8s/01-secrets.yaml
kubectl apply -f deploy/k8s/02-configmaps.yaml

# 部署基礎設施服務
kubectl apply -f deploy/k8s/infra/postgres.yaml
kubectl apply -f deploy/k8s/infra/mongo.yaml
kubectl apply -f deploy/k8s/infra/redis.yaml
kubectl apply -f deploy/k8s/infra/keycloak.yaml

# 等待 PostgreSQL 就緒
kubectl wait --for=condition=ready pod -l app=postgres -n aiops --timeout=60s

# 等待 Keycloak 就緒（需要較長時間）
kubectl wait --for=condition=ready pod -l app=keycloak -n aiops --timeout=180s
```

---

## 步驟四：初始化資料庫 Schema

```powershell
# 執行一次性 Job（啟用 pgvector 並建立所有資料表）
kubectl apply -f deploy/k8s/jobs/postgres-init.yaml

# 等待完成
kubectl wait --for=condition=complete job/postgres-init -n aiops --timeout=60s

# 確認完成
kubectl logs job/postgres-init -n aiops
```

---

## 步驟五：設定 Keycloak Realm（一次性）

> 這個步驟與 Docker Compose 指南的 Keycloak 設定完全相同，  
> 只是端口從 8090 改為 **30090**（NodePort）。

```powershell
# 取得管理員 Token
$TOKEN = (curl -s -X POST http://localhost:30090/realms/master/protocol/openid-connect/token `
  -d "client_id=admin-cli&username=admin&password=aiops_keycloak_admin&grant_type=password" `
  | ConvertFrom-Json).access_token

# 建立 aiops realm
curl -s -X POST http://localhost:30090/admin/realms `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{"realm":"aiops","enabled":true}'

# 建立 aiops-backend 用戶端
curl -s -X POST http://localhost:30090/admin/realms/aiops/clients `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"clientId":"aiops-backend","enabled":true,"clientAuthenticatorType":"client-secret","secret":"aiops-backend-secret-2024","serviceAccountsEnabled":true,"publicClient":false}'

# 建立 aiops-frontend 用戶端（redirect URI 改為 port 80，走 Ingress）
curl -s -X POST http://localhost:30090/admin/realms/aiops/clients `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"clientId":"aiops-frontend","enabled":true,"clientAuthenticatorType":"client-secret","secret":"aiops-frontend-secret-2024","standardFlowEnabled":true,"publicClient":false,"redirectUris":["http://localhost/api/auth/callback/keycloak"],"webOrigins":["http://localhost"]}'

# 建立 Realm Roles
curl -s -X POST http://localhost:30090/admin/realms/aiops/roles `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"IT_ADMIN"}'
curl -s -X POST http://localhost:30090/admin/realms/aiops/roles `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"PE"}'
curl -s -X POST http://localhost:30090/admin/realms/aiops/roles `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"ON_DUTY"}'

# 新增 roles claim Protocol Mapper
$CLIENT_ID = (curl -s "http://localhost:30090/admin/realms/aiops/clients?clientId=aiops-frontend" `
  -H "Authorization: Bearer $TOKEN" | ConvertFrom-Json)[0].id
curl -s -X POST "http://localhost:30090/admin/realms/aiops/clients/$CLIENT_ID/protocol-mappers/models" `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"realm-roles-claim","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","config":{"claim.name":"roles","jsonType.label":"String","multivalued":"true","userinfo.token.claim":"true","id.token.claim":"true","access.token.claim":"true"}}'

# 建立測試使用者
curl -s -X POST http://localhost:30090/admin/realms/aiops/users `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"username":"admin@aiops.local","email":"admin@aiops.local","enabled":true,"emailVerified":true,"credentials":[{"type":"password","value":"Admin1234!","temporary":false}]}'

$USER_ID = (curl -s "http://localhost:30090/admin/realms/aiops/users?username=admin@aiops.local" `
  -H "Authorization: Bearer $TOKEN" | ConvertFrom-Json)[0].id
$ROLE_ID = (curl -s "http://localhost:30090/admin/realms/aiops/roles/IT_ADMIN" `
  -H "Authorization: Bearer $TOKEN" | ConvertFrom-Json).id
curl -s -X POST "http://localhost:30090/admin/realms/aiops/users/$USER_ID/role-mappings/realm" `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d "[{`"id`":`"$ROLE_ID`",`"name`":`"IT_ADMIN`"}]"
```

---

## 步驟六：部署應用服務 + Ingress

```powershell
kubectl apply -f deploy/k8s/apps/ontology-simulator.yaml
kubectl apply -f deploy/k8s/apps/java-api.yaml
kubectl apply -f deploy/k8s/apps/java-scheduler.yaml
kubectl apply -f deploy/k8s/apps/python-sidecar.yaml
kubectl apply -f deploy/k8s/apps/aiops-app.yaml
kubectl apply -f deploy/k8s/ingress.yaml
```

等待所有 Pod 就緒：
```powershell
kubectl get pods -n aiops -w
# 等待全部 STATUS = Running，READY = 1/1
```

---

## 步驟七：驗證

```powershell
# 查看所有資源
kubectl get all -n aiops

# 查看 Ingress
kubectl get ingress -n aiops
# ADDRESS 欄位應顯示 localhost
```

| 驗證項目 | URL |
|---|---|
| 前端主頁（應跳轉 Keycloak 登入）| http://localhost |
| Keycloak Admin UI | http://localhost:30090（admin / aiops_keycloak_admin）|
| Java API 健康檢查 | http://localhost/api/v1/health（透過 Ingress）|

**登入帳號：** `admin@aiops.local` / `Admin1234!`

---

## 連接埠對照

| 連接方式 | 位址 | 說明 |
|---|---|---|
| 前端 | http://localhost | 透過 NGINX Ingress（port 80）|
| Keycloak Admin | http://localhost:30090 | NodePort，不經 Ingress |
| Postgres（kubectl port-forward） | localhost:5432 | `kubectl port-forward svc/postgres 5432:5432 -n aiops` |
| Mongo（kubectl port-forward） | localhost:27017 | `kubectl port-forward svc/mongo 27017:27017 -n aiops` |

---

## URL 與 Docker Compose 的差異

| 設定值 | Docker Compose | Kubernetes |
|---|---|---|
| Keycloak 外部 URL | `http://localhost:8090` | `http://localhost:30090` |
| 前端 URL | `http://localhost:8000` | `http://localhost` |
| Keycloak redirect URI | `http://localhost:8000/api/auth/callback/keycloak` | `http://localhost/api/auth/callback/keycloak` |
| 容器間通訊 | `http://keycloak:8080` | `http://keycloak:8080`（相同）|

---

## 常用維運指令

```powershell
# 查看某服務的 Log
kubectl logs -l app=aiops-java-api -n aiops --tail=50 -f

# 重啟某服務（觸發 rolling restart）
kubectl rollout restart deployment/aiops-python-sidecar -n aiops

# 修改 Secret 後套用
kubectl apply -f deploy/k8s/01-secrets.yaml
kubectl rollout restart deployment/aiops-java-api -n aiops

# 修改 ConfigMap 後套用
kubectl apply -f deploy/k8s/02-configmaps.yaml
kubectl rollout restart deployment/aiops-app -n aiops

# 刪除全部資源（保留 PVC 資料）
kubectl delete -f deploy/k8s/apps/ -n aiops
kubectl delete -f deploy/k8s/infra/ -n aiops

# 完全重置（包含資料）
kubectl delete namespace aiops

# 重新執行 DB 初始化（先刪除舊 Job）
kubectl delete job postgres-init -n aiops
kubectl apply -f deploy/k8s/jobs/postgres-init.yaml
```

---

## 更換 LLM 提供商

修改 `deploy/k8s/02-configmaps.yaml` 中的 `LLM_PROVIDER` 欄位後重新套用：

```powershell
# 編輯 02-configmaps.yaml，修改：
#   LLM_PROVIDER: "ollama"
#   OLLAMA_BASE_URL: "http://host.docker.internal:11434/v1"
#   OLLAMA_MODEL: "qwen3:latest"

kubectl apply -f deploy/k8s/02-configmaps.yaml
kubectl rollout restart deployment/aiops-python-sidecar -n aiops
```

若使用 Anthropic，在 `01-secrets.yaml` 更新 `anthropic-api-key` 後：
```powershell
kubectl apply -f deploy/k8s/01-secrets.yaml
kubectl rollout restart deployment/aiops-python-sidecar -n aiops
```

---

## 常見問題

### Q: Pod 一直 CrashLoopBackOff

```powershell
kubectl describe pod <pod-name> -n aiops
kubectl logs <pod-name> -n aiops --previous
```

常見原因：映像未加上 `k8s` 標籤，或 `imagePullPolicy: Never` 找不到本地映像。  
確認：`docker images | Select-String "k8s"`

### Q: Ingress 沒有 ADDRESS

ingress-nginx controller 可能還沒就緒：
```powershell
kubectl get pods -n ingress-nginx
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
```

### Q: Keycloak Pod 一直 Pending

StorageClass `hostpath` 不存在（某些 Docker Desktop 版本名稱不同）：
```powershell
kubectl get storageclass
# 找到可用的 StorageClass 名稱，修改 infra/keycloak.yaml 中的 storageClassName
```

### Q: Java API Pod readiness 失敗

Spring Boot 啟動需要時間（最多 60 秒）。查看啟動 Log：
```powershell
kubectl logs -l app=aiops-java-api -n aiops -f
```
若出現 DB 連線錯誤，確認 postgres Pod 已 Ready：
```powershell
kubectl get pod -l app=postgres -n aiops
```

---

*最後更新：2026-05-14*
