# AIOps Platform — Docker 本地部署指南

本文件適用於在本機以 Docker Compose 啟動完整 AIOps 平台的人員。  
全程約需 **20–30 分鐘**（首次 build 時間較長）。

---

## 前置需求

| 工具 | 版本需求 | 說明 |
|---|---|---|
| Docker Desktop | 4.x 以上 | 確保 Docker daemon 已啟動 |
| Git | 任意版本 | 用於 clone 專案 |
| curl | 任意版本（PowerShell 內建） | 用於設定 Keycloak |

> **Windows 使用者注意**：以下指令皆使用 **PowerShell**，請勿使用 Git Bash（會造成路徑解析問題）。

---

## 整體架構速覽

```
瀏覽器 :8000
  └─ aiops-app (Next.js)          ── 前端 + 認證代理
       └─ aiops-java-api :8002    ── 主業務 API + 資料庫
            └─ aiops-python-sidecar :8050  ── AI Agent 引擎
       └─ ontology-simulator :8012 ── 設備資料模擬器

基礎設施：
  postgres :5432   (pgvector)
  mongo    :27018
  redis    :6379
  keycloak :8090   (SSO 認證)
```

---

## 步驟一：Clone 專案

```powershell
git clone <YOUR_REPO_URL>
cd ai-ops-agentic-platform
```

---

## 步驟二：拉取基礎 Docker 映像

以下映像不需要自行 build，直接從 Docker Hub 拉取：

```powershell
docker pull pgvector/pgvector:pg17
docker pull mongo:7
docker pull redis:7-alpine
docker pull quay.io/keycloak/keycloak:25.0
```

> **pgvector/pgvector:pg17** 是標準 PostgreSQL 17 + pgvector 向量搜尋擴充套件，  
> 不是另一個資料庫，只需啟動這一個容器即可。

---

## 步驟三：複製並填寫設定檔

從專案根目錄執行，複製所有範例設定：

```powershell
cp deploy/docker/aiops-app/config/.env.example            deploy/docker/aiops-app/config/.env
cp deploy/docker/java-backend/config/app.env.example      deploy/docker/java-backend/config/app.env
cp deploy/docker/java-scheduler/config/app.env.example    deploy/docker/java-scheduler/config/app.env
cp deploy/docker/python-sidecar/config/app.env.example    deploy/docker/python-sidecar/config/app.env
cp deploy/docker/ontology-simulator/config/app.env.example deploy/docker/ontology-simulator/config/app.env
```

### 3-A. Shared Token 對照表

以下 Token 必須在多個服務間**完全一致**，請選定一組值後統一填入：

| Token 名稱 | 需要填入的檔案 | 說明 |
|---|---|---|
| DB 密碼 | docker-compose.yml + java-backend + java-scheduler | PostgreSQL 帳密 |
| `JAVA_INTERNAL_TOKEN` | java-backend + python-sidecar + aiops-app `INTERNAL_API_TOKEN` | 前端→Java 內部呼叫 Token |
| `PYTHON_SIDECAR_TOKEN` / `SERVICE_TOKEN` | java-backend + java-scheduler + python-sidecar | Java→Sidecar 呼叫 Token |
| `AIOPS_SCHEDULER_INTERNAL_TOKEN` | java-backend + java-scheduler | Scheduler 服務間 Token |
| `AIOPS_OIDC_UPSERT_SECRET` | java-backend + aiops-app | Keycloak 使用者同步密鑰 |

> 本指南使用的測試值（**生產環境請換成強密碼**）：

| Token | 本指南使用的測試值 |
|---|---|
| DB 密碼 | `aiops_db_pass` |
| JAVA_INTERNAL_TOKEN | `aiops_internal_token_2024` |
| PYTHON_SIDECAR_TOKEN | `aiops_sidecar_token_2024` |
| AIOPS_SCHEDULER_INTERNAL_TOKEN | `aiops_scheduler_token_2024` |
| AIOPS_OIDC_UPSERT_SECRET | `aiops_upsert_secret_2024` |
| NEXTAUTH_SECRET | `aiops_nextauth_secret_change_me_!!` |
| Keycloak backend client secret | `aiops-backend-secret-2024` |
| Keycloak frontend client secret | `aiops-frontend-secret-2024` |

---

### 3-B. `deploy/docker/aiops-app/config/.env`

```env
FASTAPI_BASE_URL=http://aiops-java-api:8080
AGENT_BASE_URL=http://aiops-python-sidecar:8080
ONTOLOGY_BASE_URL=http://ontology-simulator:8080
INTERNAL_API_TOKEN=aiops_internal_token_2024
NEXTAUTH_URL=http://localhost:8000
NEXTAUTH_SECRET=aiops_nextauth_secret_change_me_!!
AIOPS_OIDC_UPSERT_SECRET=aiops_upsert_secret_2024
AIOPS_AUTH_REQUIRED=1
OIDC_KEYCLOAK_CLIENT_ID=aiops-frontend
OIDC_KEYCLOAK_CLIENT_SECRET=aiops-frontend-secret-2024
OIDC_KEYCLOAK_ISSUER=http://localhost:8090/realms/aiops
OIDC_KEYCLOAK_ISSUER_INTERNAL=http://keycloak:8080/realms/aiops
NODE_ENV=production
PORT=8080
HOSTNAME=0.0.0.0
```

> `OIDC_KEYCLOAK_ISSUER` → 瀏覽器看到的外部網址（localhost）  
> `OIDC_KEYCLOAK_ISSUER_INTERNAL` → 容器內部互通網址（Docker DNS）

---

### 3-C. `deploy/docker/java-backend/config/app.env`

```env
AIOPS_PROFILE=prod
AIOPS_JAVA_PORT=8080
DB_URL=jdbc:postgresql://postgres:5432/aiops
DB_USER=aiops
DB_PASSWORD=aiops_db_pass
JWT_SECRET=CHANGE_ME_32_CHARS_OR_MORE_____________
AUTH_MODE=oidc
OIDC_ISSUER=http://localhost:8090/realms/aiops
OIDC_CLIENT_ID=aiops-backend
OIDC_CLIENT_SECRET=aiops-backend-secret-2024
OIDC_ROLE_CLAIM=roles
OIDC_JWK_URI=http://keycloak:8080/realms/aiops/protocol/openid-connect/certs
AIOPS_OIDC_UPSERT_SECRET=aiops_upsert_secret_2024
AIOPS_SHARED_SECRET_TOKEN=
PYTHON_SIDECAR_URL=http://aiops-python-sidecar:8080
PYTHON_SIDECAR_TOKEN=aiops_sidecar_token_2024
JAVA_INTERNAL_TOKEN=aiops_internal_token_2024
JAVA_INTERNAL_ALLOWED_IPS=
AIOPS_SCHEDULER_BASE_URL=http://aiops-java-scheduler:8080
AIOPS_SCHEDULER_INTERNAL_TOKEN=aiops_scheduler_token_2024
CORS_ALLOWED_ORIGINS=http://localhost:8000
```

> `JAVA_INTERNAL_ALLOWED_IPS=`（空值）：停用 IP 白名單，因為 Docker 容器 IP 動態分配。  
> `JWT_SECRET`：請填入至少 32 個字元的任意字串。

---

### 3-D. `deploy/docker/java-scheduler/config/app.env`

```env
DB_URL=jdbc:postgresql://postgres:5432/aiops
DB_USER=aiops
DB_PASSWORD=aiops_db_pass
AIOPS_SCHEDULER_INTERNAL_TOKEN=aiops_scheduler_token_2024
PYTHON_SIDECAR_URL=http://aiops-python-sidecar:8080
PYTHON_SIDECAR_TOKEN=aiops_sidecar_token_2024
ONTOLOGY_SIM_URL=http://ontology-simulator:8080
REDIS_HOST=redis
REDIS_PORT=6379
```

---

### 3-E. `deploy/docker/python-sidecar/config/app.env`

這個檔案有兩種填法，根據你使用的 **LLM 選項**選擇其中一種：

#### 選項 A：使用 Anthropic Claude（雲端 API，需要 API Key）

```env
SERVICE_TOKEN=aiops_sidecar_token_2024
SIDECAR_PORT=8080
ALLOWED_CALLERS=
JAVA_API_URL=http://aiops-java-api:8080
JAVA_INTERNAL_TOKEN=aiops_internal_token_2024

# LLM 設定
LLM_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxxxxxxxxxxx   # 填入你的 Anthropic Key
ANTHROPIC_MODEL=claude-sonnet-4-6
ANTHROPIC_MAX_TOKENS=8096

# 背景任務（初始可停用）
EVENT_POLLER_ENABLED=0
NATS_SUBSCRIBER_ENABLED=0
```

> 取得 Anthropic API Key：前往 [https://console.anthropic.com](https://console.anthropic.com) → API Keys。

#### 選項 B：使用本地 Ollama（Qwen3 或其他本地模型，免費）

**前置：先在本機安裝並啟動 Ollama**

```powershell
# 安裝 Ollama（前往 https://ollama.com 下載安裝程式）
# 安裝後拉取模型：
ollama pull qwen3          # 主要 LLM（約 5GB，視版本而定）
ollama pull bge-m3         # 向量嵌入模型（必須，1024 維度）
```

```env
SERVICE_TOKEN=aiops_sidecar_token_2024
SIDECAR_PORT=8080
ALLOWED_CALLERS=
JAVA_API_URL=http://aiops-java-api:8080
JAVA_INTERNAL_TOKEN=aiops_internal_token_2024

# LLM 設定
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
OLLAMA_MODEL=qwen3:latest
OLLAMA_EMBEDDING_MODEL=bge-m3

# 背景任務（初始可停用）
EVENT_POLLER_ENABLED=0
NATS_SUBSCRIBER_ENABLED=0
```

> `host.docker.internal` 是 Docker Desktop for Windows/Mac 的特殊 DNS，  
> 讓容器可以連回到宿主機（你的電腦）上的 Ollama。  
> `OLLAMA_BASE_URL` 結尾必須是 `/v1`（OpenAI 相容 API 路徑）。

---

### 3-F. `deploy/docker/ontology-simulator/config/app.env`

```env
PORT=8080
MONGODB_URI=mongodb://mongo:27017
```

---

## 步驟四：設定 Keycloak（一次性，首次啟動前完成）

先單獨啟動 Keycloak 容器：

```powershell
docker compose -f deploy/docker-compose.yml up keycloak -d
```

等待約 **30 秒**讓 Keycloak 完全啟動，再執行以下設定指令：

```powershell
# 1. 取得管理員 Token
$TOKEN = (curl -s -X POST http://localhost:8090/realms/master/protocol/openid-connect/token `
  -d "client_id=admin-cli&username=admin&password=aiops_keycloak_admin&grant_type=password" `
  | ConvertFrom-Json).access_token

# 確認 Token 有拿到（應顯示一長串字串）
echo $TOKEN
```

```powershell
# 2. 建立 aiops realm
curl -s -X POST http://localhost:8090/admin/realms `
  -H "Authorization: Bearer $TOKEN" `
  -H "Content-Type: application/json" `
  -d '{"realm":"aiops","enabled":true}'
```

```powershell
# 3. 建立 aiops-backend 用戶端（供 Java API 驗證 JWT）
curl -s -X POST http://localhost:8090/admin/realms/aiops/clients `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"clientId":"aiops-backend","enabled":true,"clientAuthenticatorType":"client-secret","secret":"aiops-backend-secret-2024","serviceAccountsEnabled":true,"publicClient":false}'
```

```powershell
# 4. 建立 aiops-frontend 用戶端（供 Next.js NextAuth 登入流程）
curl -s -X POST http://localhost:8090/admin/realms/aiops/clients `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"clientId":"aiops-frontend","enabled":true,"clientAuthenticatorType":"client-secret","secret":"aiops-frontend-secret-2024","standardFlowEnabled":true,"publicClient":false,"redirectUris":["http://localhost:8000/api/auth/callback/keycloak"],"webOrigins":["http://localhost:8000"]}'
```

```powershell
# 5. 建立 Realm Roles（三個角色）
curl -s -X POST http://localhost:8090/admin/realms/aiops/roles `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"IT_ADMIN"}'

curl -s -X POST http://localhost:8090/admin/realms/aiops/roles `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"PE"}'

curl -s -X POST http://localhost:8090/admin/realms/aiops/roles `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"ON_DUTY"}'
```

```powershell
# 6. 新增 roles claim 到 aiops-frontend JWT（讓 Java 能讀取角色）
# 先取得 aiops-frontend 的內部 ID
$CLIENT_ID = (curl -s "http://localhost:8090/admin/realms/aiops/clients?clientId=aiops-frontend" `
  -H "Authorization: Bearer $TOKEN" | ConvertFrom-Json)[0].id

# 新增 Protocol Mapper（將 realm roles 放入 JWT 的 roles 欄位）
curl -s -X POST "http://localhost:8090/admin/realms/aiops/clients/$CLIENT_ID/protocol-mappers/models" `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"name":"realm-roles-claim","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","config":{"claim.name":"roles","jsonType.label":"String","multivalued":"true","userinfo.token.claim":"true","id.token.claim":"true","access.token.claim":"true"}}'
```

```powershell
# 7. 建立測試使用者（IT_ADMIN 角色）
curl -s -X POST http://localhost:8090/admin/realms/aiops/users `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d '{"username":"admin@aiops.local","email":"admin@aiops.local","enabled":true,"emailVerified":true,"credentials":[{"type":"password","value":"Admin1234!","temporary":false}]}'

# 取得使用者 ID 並指派 IT_ADMIN 角色
$USER_ID = (curl -s "http://localhost:8090/admin/realms/aiops/users?username=admin@aiops.local" `
  -H "Authorization: Bearer $TOKEN" | ConvertFrom-Json)[0].id

$ROLE_ID = (curl -s "http://localhost:8090/admin/realms/aiops/roles/IT_ADMIN" `
  -H "Authorization: Bearer $TOKEN" | ConvertFrom-Json).id

curl -s -X POST "http://localhost:8090/admin/realms/aiops/users/$USER_ID/role-mappings/realm" `
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" `
  -d "[{`"id`":`"$ROLE_ID`",`"name`":`"IT_ADMIN`"}]"
```

> **可選：新增其他角色的測試使用者**（PE、ON_DUTY），方法相同，只需更換 username 和角色名稱。

---

## 步驟五：Build 所有自定義映像

```powershell
docker compose -f deploy/docker-compose.yml build
```

- 首次 build 約需 **10–20 分鐘**（Maven 下載依賴、npm 安裝套件）
- 後續再 build 會使用 layer cache，速度大幅加快
- 如果只修改了某個服務的設定，不需要重新 build（設定檔是以 volume 掛載）

---

## 步驟六：初始化資料庫 Schema

首次啟動前，需要先執行 SQL 初始化腳本，啟用 pgvector 擴充套件並建立所有表格：

```powershell
# 先啟動 postgres
docker compose -f deploy/docker-compose.yml up postgres -d

# 等 10 秒讓 postgres 就緒
Start-Sleep -Seconds 10

# 執行初始化腳本
docker exec -i deploy-postgres-1 psql -U aiops < deploy/docker/postgres/init.sql
```

> 此腳本使用 `IF NOT EXISTS`，重複執行是安全的，不會刪除已有資料。  
> 主要作用：啟用 `vector` 擴充套件，並確保所有表格（包含向量欄位的 AI 記憶體資料表）存在。

---

## 步驟七：啟動完整服務堆疊

```powershell
docker compose -f deploy/docker-compose.yml up -d
```

啟動順序由 `depends_on` + healthcheck 自動控制：

```
1. postgres, mongo, redis, keycloak  （同時啟動）
2. ontology-simulator                （等 mongo healthy）
3. aiops-java-api                    （等 postgres healthy + keycloak started）
4. aiops-java-scheduler              （等 java-api healthy + redis healthy）
5. aiops-python-sidecar              （等 java-api healthy）
6. aiops-app                         （等 java-api healthy + python-sidecar healthy）
```

全部容器達到 healthy 狀態約需 **2–5 分鐘**。

---

## 步驟八：驗證服務狀態

```powershell
# 查看所有容器狀態（應全部顯示 Up (healthy)）
docker compose -f deploy/docker-compose.yml ps
```

逐項確認健康狀態：

```powershell
# Java API（Spring Boot Actuator）
curl http://localhost:8002/actuator/health
# 預期回傳：{"status":"UP"}

# Python Sidecar（需要 Token Header）
curl -H "X-Service-Token: aiops_sidecar_token_2024" http://localhost:8050/internal/health
# 預期回傳：200 OK

# Ontology Simulator
curl http://localhost:8012/api/v1/status
# 預期回傳：200 OK

# 前端（瀏覽器開啟）
# http://localhost:8000  → 應自動跳轉到 Keycloak 登入頁面
```

---

## 步驟九：登入測試

在瀏覽器開啟 **http://localhost:8000**

| 帳號 | 密碼 | 角色 | 說明 |
|---|---|---|---|
| `admin@aiops.local` | `Admin1234!` | IT_ADMIN | 完整管理權限，可使用所有 AI 功能 |

> **角色說明：**
> - `IT_ADMIN`：最高權限，可建立 Pipeline、編輯 Skill、讀寫記憶體
> - `PE`：Process Engineer，可使用 AI Agent + 建立 Pipeline，不能管理系統設定
> - `ON_DUTY`：值班工程師，唯讀模式，只能使用已發布的 Skill，不能建立新的 Pipeline

---

## 連接埠對照表

| 宿主機埠 | 服務 | 說明 |
|---|---|---|
| 8000 | aiops-app | Next.js 前端，主要入口 |
| 8002 | aiops-java-api | Spring Boot 主 API |
| 8003 | aiops-java-scheduler | 排程服務 |
| 8050 | aiops-python-sidecar | AI Agent 引擎 |
| 8012 | ontology-simulator | 設備資料模擬器 |
| 8090 | Keycloak | Admin UI（帳號：admin / aiops_keycloak_admin）|
| 5432 | PostgreSQL | 資料庫（pgvector） |
| 27018 | MongoDB | 文件資料庫（Simulator 用） |
| 6379 | Redis | 快取 / 排程佇列 |

---

## 常用維運指令

```powershell
# 查看某服務的即時 Log
docker logs deploy-aiops-java-api-1 -f --tail 50

# 重啟單一服務（不重新 build）
docker compose -f deploy/docker-compose.yml restart aiops-python-sidecar

# 修改設定後重啟某服務
docker compose -f deploy/docker-compose.yml up -d --no-deps aiops-python-sidecar

# 重新 build 並重啟某服務
docker compose -f deploy/docker-compose.yml build aiops-java-api
docker compose -f deploy/docker-compose.yml up -d --no-deps aiops-java-api

# 停止全部服務（保留資料 volume）
docker compose -f deploy/docker-compose.yml down

# 停止全部服務並清除所有資料（完全重置）
docker compose -f deploy/docker-compose.yml down -v

# 重置 PostgreSQL schema（如資料庫結構損毀）
docker exec deploy-postgres-1 psql -U aiops -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
docker exec -i deploy-postgres-1 psql -U aiops < deploy/docker/postgres/init.sql
docker restart deploy-aiops-java-api-1
```

---

## LLM 選項切換

修改 `deploy/docker/python-sidecar/config/app.env` 後，重啟 sidecar 即可生效：

```powershell
docker compose -f deploy/docker-compose.yml up -d --no-deps aiops-python-sidecar
```

### 切換到 Anthropic Claude

```env
LLM_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxx
ANTHROPIC_MODEL=claude-sonnet-4-6
```

### 切換到本地 Ollama（Qwen3）

```env
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
OLLAMA_MODEL=qwen3:latest
OLLAMA_EMBEDDING_MODEL=bge-m3
```

### 可用 Ollama 模型參考

| 模型 | 指令 | 大小 | 工具呼叫支援 |
|---|---|---|---|
| Qwen3 8B | `ollama pull qwen3:8b` | ~5 GB | ✅ |
| Qwen3 14B | `ollama pull qwen3:14b` | ~9 GB | ✅ |
| Llama3.1 8B | `ollama pull llama3.1:8b` | ~5 GB | ✅ |
| bge-m3（嵌入模型） | `ollama pull bge-m3` | ~1.2 GB | N/A（必須安裝） |

> ⚠️ **嵌入模型 bge-m3 是必須的**：AI Agent 的語意記憶（agent_knowledge 資料表）使用 1024 維向量，  
> bge-m3 輸出正好是 1024 維。若不安裝，知識庫搜尋功能將無法運作。

---

## 常見問題排除

### Q: Keycloak 登入後出現「Configuration」錯誤

代表 NextAuth 無法連到 Keycloak。請確認：
1. `OIDC_KEYCLOAK_ISSUER` 使用 `localhost:8090`（瀏覽器可存取）
2. `OIDC_KEYCLOAK_ISSUER_INTERNAL` 使用 `keycloak:8080`（容器內部 DNS）
3. Realm 名稱是否正確（應為 `aiops`）

### Q: AI Agent 對話無回應 / 出現 401 或 403 錯誤

- **401**：Bearer Token 類型不正確。確認 `auth-proxy.ts` 優先使用 `idpAccessToken`（Keycloak JWT），而非 `javaJwt`。
- **403**：JWT 中缺少 `roles` 欄位。確認步驟四第 6 步的 Protocol Mapper 有建立成功。

### Q: AI Agent 回應 Anthropic 401 / 402 錯誤

- **401**：`ANTHROPIC_API_KEY` 無效，請確認填入正確的 API Key。
- **402 / 400**：Anthropic 帳戶餘額不足，請前往 [console.anthropic.com](https://console.anthropic.com) 加值。
- 替代方案：改用本地 Ollama（見上方 LLM 選項切換章節）。

### Q: postgres 容器健康但 Java 啟動後資料庫表格不存在

執行初始化腳本後重啟 Java：
```powershell
docker exec -i deploy-postgres-1 psql -U aiops < deploy/docker/postgres/init.sql
docker restart deploy-aiops-java-api-1
```

### Q: Port 已被佔用（address already in use）

查看佔用的 Port 並關閉對應程式，或修改 `docker-compose.yml` 中的 host port（左側數字）。  
常見衝突：
- 27017：本機 MongoDB → 已在 compose 中改為 27018
- 8080：各種本地服務 → Keycloak 已改為 8090

### Q: Build 失敗 — npm ci 出現 peer dependency 錯誤

React 19 peer dep 衝突，`aiops-app/Dockerfile` 中已加入 `--legacy-peer-deps` 旗標，  
若出現此問題請確認 Dockerfile 中有這行：
```dockerfile
RUN npm ci --legacy-peer-deps
```

---

*最後更新：2026-05-14*
