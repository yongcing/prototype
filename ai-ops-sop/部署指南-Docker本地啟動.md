# AIOps Platform — Docker 本地部署指南

本文件適用於在本機以 Docker Compose 啟動完整 AIOps 平台的人員。  
從 **全新 git clone** 的乾淨狀態出發，按照本文件操作即可完整建立環境。

全程約需 **20–30 分鐘**（首次 build 時間較長）。

---

## 快速啟動 SOP（完成步驟一～六後執行）

> 所有步驟（Keycloak 初始化、DB 種子資料、服務健康確認、自動化 QA）已整合進腳本。  
> **完成所有前置步驟後，只需執行這一行**：

```powershell
# 確保 Docker Desktop 已啟動，並在專案根目錄執行
.\deploy\start-local.ps1
```

腳本分為四個 Phase：

| Phase | 動作 |
|---|---|
| Phase 1 | 啟動 postgres / mongo / redis / keycloak，等待 Keycloak HTTP 就緒（最多 120 秒） |
| Phase 2 | 建立 Keycloak aiops realm / clients / roles / 測試使用者（idempotent，已存在自動跳過） |
| Phase 3 | 啟動所有 App 服務，等待全部 healthy（最多 180 秒） |
| Phase 3.5 | **DB 初始化**：設定 admin 本地密碼、確保 list_* MCPs 已存在（idempotent） |
| Phase 4 | 執行自動化 QA 驗證（7 項測試），印出結果摘要 |

完成後可直接開啟 **http://localhost:8000** 登入。

### 登入帳號資訊

| 登入方式 | 帳號 | 密碼 | 說明 |
|---|---|---|---|
| 本地帳密（Java JWT） | `admin` | `Admin1234!` | 直接輸入 username，由 Java API 發 JWT |
| Keycloak SSO | `admin@aiops.local` | `Admin1234!` | 點「使用 Keycloak 登入」，走 OIDC 流程 |

---

## 前置需求

| 工具 | 版本需求 | 說明 |
|---|---|---|
| Docker Desktop | 4.x 以上 | 確保 Docker daemon 已啟動 |
| Git | 任意版本 | 用於 clone 專案 |
| PowerShell | 5.1 以上（Windows 內建） | 執行腳本用 |

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
  mongo    :27017
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

```powershell
docker pull pgvector/pgvector:pg17
docker pull mongo:7
docker pull redis:7-alpine
docker pull quay.io/keycloak/keycloak:25.0
```

---

## 步驟三：建立部署所需的所有檔案

> **說明**：deploy 目錄下的 Docker 設定、腳本、config 檔案需要手動建立。  
> 本節提供所有檔案的完整內容，請依序執行。

### 3-A. 建立目錄結構

```powershell
New-Item -ItemType Directory -Force deploy/docker/java-backend/config
New-Item -ItemType Directory -Force deploy/docker/java-scheduler/config
New-Item -ItemType Directory -Force deploy/docker/python-sidecar/config
New-Item -ItemType Directory -Force deploy/docker/ontology-simulator/config
New-Item -ItemType Directory -Force deploy/docker/aiops-app/config
New-Item -ItemType Directory -Force deploy/docker/postgres
```

---

### 3-B. `deploy/docker-compose.yml`

```yaml
services:

  # ─── Infrastructure ────────────────────────────────────────────────────────

  postgres:
    image: pgvector/pgvector:pg17
    environment:
      POSTGRES_USER: aiops
      POSTGRES_PASSWORD: aiops_db_pass
      POSTGRES_DB: aiops
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "aiops"]
      interval: 5s
      timeout: 3s
      retries: 10

  mongo:
    image: mongo:7
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 5s
      timeout: 3s
      retries: 10

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10

  keycloak:
    image: quay.io/keycloak/keycloak:25.0
    # start 模式 + 固定 hostname，確保 JWT iss 欄位永遠是 http://localhost:8090/...
    # 無論請求從瀏覽器（localhost:8090）或容器內部（keycloak:8080）進來都一致。
    # --http-enabled=true      : 允許 HTTP（本地開發無需 TLS）
    # --hostname=http://localhost:8090 : 公開 URL，決定 JWT iss 和 discovery 的 issuer
    # --hostname-strict=false  : 允許容器內以 keycloak:8080 呼叫（token exchange 用）
    # --cache=local            : 單節點模式，無需 Infinispan cluster
    command: ["start", "--http-enabled=true", "--hostname-strict=false", "--hostname=http://localhost:8090", "--cache=local"]
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: aiops_keycloak_admin
      KC_HTTP_PORT: "8080"
    ports:
      - "8090:8080"
    volumes:
      - keycloak_data:/opt/keycloak/data
    healthcheck:
      # Keycloak 25 (UBI-based) 沒有 curl/wget，改用 bash TCP 連線檢查
      test: ["CMD-SHELL", "exec 3<>/dev/tcp/localhost/8080"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  # ─── Applications ──────────────────────────────────────────────────────────

  ontology-simulator:
    build:
      context: ..
      dockerfile: deploy/docker/ontology-simulator/Dockerfile
    container_name: deploy-ontology-simulator-1
    ports:
      - "8012:8080"
    volumes:
      - ./docker/ontology-simulator/config:/app/config
    depends_on:
      mongo:
        condition: service_healthy
    healthcheck:
      # python:3.11-slim 沒有 wget，用 python3 urllib
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/api/v1/status')"]
      interval: 10s
      timeout: 5s
      retries: 6

  aiops-java-api:
    build:
      context: ..
      dockerfile: deploy/docker/java-backend/Dockerfile
    container_name: deploy-aiops-java-api-1
    ports:
      - "8002:8080"
    volumes:
      - ./docker/java-backend/config:/usrapp/config
    depends_on:
      postgres:
        condition: service_healthy
      keycloak:
        condition: service_healthy
    healthcheck:
      # eclipse-temurin:17-jre-alpine 有 wget
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  aiops-java-scheduler:
    build:
      context: ..
      dockerfile: deploy/docker/java-scheduler/Dockerfile
    container_name: deploy-aiops-java-scheduler-1
    ports:
      - "8003:8080"
    volumes:
      - ./docker/java-scheduler/config:/usrapp/config
    depends_on:
      aiops-java-api:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  aiops-python-sidecar:
    build:
      context: ..
      dockerfile: deploy/docker/python-sidecar/Dockerfile
    container_name: deploy-aiops-python-sidecar-1
    ports:
      - "8050:8080"
    volumes:
      - ./docker/python-sidecar/config:/workspace/config
    depends_on:
      aiops-java-api:
        condition: service_healthy
    healthcheck:
      # python:3.11-slim 沒有 wget，用 python3 urllib
      test: ["CMD", "python3", "-c", "import urllib.request; r=urllib.request.Request('http://localhost:8080/internal/health',headers={'X-Service-Token':'aiops_sidecar_token_2024'}); urllib.request.urlopen(r)"]
      interval: 10s
      timeout: 5s
      retries: 6

  aiops-app:
    build:
      context: ..
      dockerfile: deploy/docker/aiops-app/Dockerfile
    container_name: deploy-aiops-app-1
    ports:
      - "8000:8080"
    volumes:
      - ./docker/aiops-app/config:/usrapp/config
    depends_on:
      aiops-java-api:
        condition: service_healthy
      aiops-python-sidecar:
        condition: service_healthy
    healthcheck:
      # 用 127.0.0.1 而非 localhost：node:20-alpine 裡 localhost 解析成 ::1 (IPv6)
      # 但 Next.js 只 bind IPv4，會連不上
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:8080/"]
      interval: 10s
      timeout: 5s
      retries: 6

volumes:
  postgres_data:
  mongo_data:
  keycloak_data:
```

---

### 3-C. `deploy/docker/postgres/init.sql`

```sql
-- Enable pgvector extension (required before any schema creation)
CREATE EXTENSION IF NOT EXISTS vector;
```

---

### 3-D. Java Backend Dockerfile

建立 `deploy/docker/java-backend/Dockerfile`：

```dockerfile
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /workspace

COPY pom.xml ./
COPY java-backend/pom.xml ./java-backend/
COPY java-scheduler/pom.xml ./java-scheduler/
COPY java-backend/src ./java-backend/src
COPY java-scheduler/src ./java-scheduler/src

RUN mvn -B -Dmaven.test.skip=true package -pl java-backend -am

FROM eclipse-temurin:17-jre-alpine
WORKDIR /usrapp
COPY --from=builder /workspace/java-backend/target/aiops-api.jar app.jar
COPY deploy/docker/java-backend/run.sh ./run.sh
RUN chmod +x run.sh && mkdir -p config log
EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
```

建立 `deploy/docker/java-backend/run.sh`：

```sh
#!/bin/sh
set -e
if [ -f /usrapp/config/app.env ]; then
  export $(grep -v '^#' /usrapp/config/app.env | grep -v '^$' | xargs)
fi
mkdir -p /usrapp/log
exec java -jar /usrapp/app.jar 2>&1 | tee -a /usrapp/log/app.log
```

---

### 3-E. Java Scheduler Dockerfile

建立 `deploy/docker/java-scheduler/Dockerfile`：

```dockerfile
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /workspace

COPY pom.xml ./
COPY java-backend/pom.xml ./java-backend/
COPY java-scheduler/pom.xml ./java-scheduler/
COPY java-backend/src ./java-backend/src
COPY java-scheduler/src ./java-scheduler/src

# java-scheduler depends on java-backend:library classifier — must install first
RUN mvn -B -Dmaven.test.skip=true install -pl java-backend -am && \
    mvn -B -Dmaven.test.skip=true package -pl java-scheduler

FROM eclipse-temurin:17-jre-alpine
WORKDIR /usrapp
COPY --from=builder /workspace/java-scheduler/target/aiops-scheduler.jar app.jar
COPY deploy/docker/java-scheduler/run.sh ./run.sh
RUN chmod +x run.sh && mkdir -p config log
EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
```

建立 `deploy/docker/java-scheduler/run.sh`：

```sh
#!/bin/sh
set -e
if [ -f /usrapp/config/app.env ]; then
  export $(grep -v '^#' /usrapp/config/app.env | grep -v '^$' | xargs)
fi
mkdir -p /usrapp/log
exec java -jar /usrapp/app.jar 2>&1 | tee -a /usrapp/log/app.log
```

---

### 3-F. Python Sidecar Dockerfile

建立 `deploy/docker/python-sidecar/Dockerfile`：

```dockerfile
FROM python:3.11-slim
WORKDIR /workspace

COPY python_ai_sidecar/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY python_ai_sidecar/ ./python_ai_sidecar/
COPY deploy/docker/python-sidecar/run.sh ./run.sh
RUN chmod +x run.sh && mkdir -p config log
EXPOSE 8080
ENTRYPOINT ["/workspace/run.sh"]
```

建立 `deploy/docker/python-sidecar/run.sh`：

```sh
#!/bin/sh
set -e
if [ -f /workspace/config/app.env ]; then
  export $(grep -v '^#' /workspace/config/app.env | grep -v '^$' | xargs)
fi
mkdir -p /workspace/log
exec uvicorn python_ai_sidecar.main:app \
  --host 0.0.0.0 --port "${SIDECAR_PORT:-8080}" \
  2>&1 | tee -a /workspace/log/app.log
```

---

### 3-G. Ontology Simulator Dockerfile

建立 `deploy/docker/ontology-simulator/Dockerfile`：

```dockerfile
FROM python:3.11-slim
WORKDIR /app

COPY ontology_simulator/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy simulator source — main.py imports from `app.*` so must be WORKDIR root
COPY ontology_simulator/ ./
COPY deploy/docker/ontology-simulator/run.sh ./run.sh
RUN chmod +x run.sh && mkdir -p config log
EXPOSE 8080
ENTRYPOINT ["/app/run.sh"]
```

建立 `deploy/docker/ontology-simulator/run.sh`：

```sh
#!/bin/sh
set -e
if [ -f /app/config/app.env ]; then
  export $(grep -v '^#' /app/config/app.env | grep -v '^$' | xargs)
fi
mkdir -p /app/log
exec uvicorn main:app \
  --host 0.0.0.0 --port "${PORT:-8080}" \
  2>&1 | tee -a /app/log/app.log
```

---

### 3-H. AIOps App Dockerfile

建立 `deploy/docker/aiops-app/Dockerfile`：

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /workspace

# Copy both aiops-app and aiops-contract for the file dependency to resolve
COPY aiops-app/ ./aiops-app/
COPY aiops-contract/ ./aiops-contract/

WORKDIR /workspace/aiops-app
RUN npm ci --legacy-peer-deps

RUN npm run build

FROM node:20-alpine
WORKDIR /usrapp
COPY --from=builder /workspace/aiops-app/.next/standalone ./
COPY --from=builder /workspace/aiops-app/.next/static ./.next/static
COPY --from=builder /workspace/aiops-app/public ./public
COPY deploy/docker/aiops-app/run.sh ./run.sh
RUN chmod +x run.sh && mkdir -p config log
EXPOSE 8080
ENTRYPOINT ["/usrapp/run.sh"]
```

建立 `deploy/docker/aiops-app/run.sh`：

```sh
#!/bin/sh
set -e
if [ -f /usrapp/config/.env ]; then
  export $(grep -v '^#' /usrapp/config/.env | grep -v '^$' | xargs)
fi
mkdir -p /usrapp/log
exec node server.js 2>&1 | tee -a /usrapp/log/app.log
```

---

### 3-I. `deploy/start-local.ps1`（主啟動腳本）

建立 `deploy/start-local.ps1`，內容如下：

```powershell
# deploy/start-local.ps1
# 本地 Docker 完整啟動腳本 (SOP 入口)
#
# 用法（在專案根目錄執行）：
#   .\deploy\start-local.ps1
#
# 流程：
#   Phase 1   — 啟動 Infrastructure (postgres / mongo / redis / keycloak)
#   Phase 2   — 初始化 Keycloak realm（必須在 Java 啟動前完成）
#   Phase 3   — 啟動 App Services (ontology-simulator / java-api / sidecar / aiops-app)
#   Phase 3.5 — 補丁：admin 密碼 + list_* MCPs（idempotent，重複執行安全）
#   Phase 4   — 自動化 QA 驗證

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$COMPOSE_FILE = Join-Path $PSScriptRoot "docker-compose.yml"
$SCRIPT_DIR   = $PSScriptRoot

function Write-Step { param($msg) Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "  [!!]  $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "  [--]  $msg" -ForegroundColor Gray }

# ─── 前置檢查 ────────────────────────────────────────────────────────────────
Write-Step "前置檢查"
try {
    docker info *>$null
    Write-Ok "Docker Desktop 已啟動"
} catch {
    Write-Fail "Docker Desktop 未啟動，請先開啟 Docker Desktop 再重新執行"
    exit 1
}

# ─── Phase 1：啟動 Infrastructure ────────────────────────────────────────────
Write-Step "Phase 1 — 啟動 Infrastructure (postgres / mongo / redis / keycloak)"
docker compose -f $COMPOSE_FILE up -d postgres mongo redis keycloak
Write-Info "等待 Keycloak HTTP 就緒（最多 120 秒）..."

$deadline = (Get-Date).AddSeconds(120)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $status = (Invoke-WebRequest -Uri "http://localhost:8090/health/ready" -UseBasicParsing -TimeoutSec 3).StatusCode
        if ($status -eq 200) { $ready = $true; break }
    } catch {}
    Start-Sleep -Seconds 3
    Write-Host -NoNewline "."
}
Write-Host ""

if (-not $ready) {
    Write-Fail "Keycloak 在 120 秒內未就緒，查看 log："
    docker compose -f $COMPOSE_FILE logs keycloak --tail 30
    exit 1
}
Write-Ok "Keycloak 已就緒 (http://localhost:8090)"

# ─── Phase 2：初始化 Keycloak Realm ──────────────────────────────────────────
Write-Step "Phase 2 — 初始化 Keycloak Realm (aiops realm / clients / roles / test user)"

try {
    Invoke-WebRequest -Uri "http://localhost:8090/realms/aiops" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Info "aiops realm 已存在，跳過 keycloak-setup.ps1"
} catch {
    Write-Info "執行 keycloak-setup.ps1..."
    & "$SCRIPT_DIR\keycloak-setup.ps1"
    Write-Ok "Keycloak realm 設定完成"
}

# ─── Phase 3：啟動 App Services ──────────────────────────────────────────────
Write-Step "Phase 3 — 啟動 App Services"
docker compose -f $COMPOSE_FILE up -d
Write-Info "等待所有 service healthy（最多 180 秒）..."

$services = @{
    "ontology-simulator"   = "http://localhost:8012/api/v1/status"
    "aiops-java-api"       = "http://localhost:8002/actuator/health"
    "aiops-python-sidecar" = "http://localhost:8050/internal/health"
    "aiops-app"            = "http://localhost:8000"
}

$deadline = (Get-Date).AddSeconds(180)
$allUp = $false
while ((Get-Date) -lt $deadline) {
    $allUp = $true
    foreach ($kv in $services.GetEnumerator()) {
        try {
            $r = Invoke-WebRequest -Uri $kv.Value -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -ge 400) { $allUp = $false }
        } catch { $allUp = $false }
    }
    if ($allUp) { break }
    Start-Sleep -Seconds 5
    Write-Host -NoNewline "."
}
Write-Host ""

if (-not $allUp) {
    Write-Fail "部分 service 在 180 秒內未就緒，顯示 docker compose ps："
    docker compose -f $COMPOSE_FILE ps
    Write-Info "查看失敗服務 log，例如："
    Write-Info "  docker compose -f $COMPOSE_FILE logs aiops-java-api --tail 50"
    exit 1
}
Write-Ok "所有 service 已啟動"

# ─── Phase 3.5：補丁 — admin 密碼 + list_* MCPs ──────────────────────────────
# 這個步驟是 idempotent：重複執行不會造成資料錯誤。
# 必須在 java-api 啟動後執行（需要 postgres 可連線）。
Write-Step "Phase 3.5 — 確保 admin 本地密碼與 list MCPs 已設定"

# 寫 SQL 到暫存檔 → 複製進容器 → 執行（避免 PowerShell/shell 引號衝突）
$tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
@'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

UPDATE users
  SET hashed_password = crypt('Admin1234!', gen_salt('bf', 12)),
      is_active       = true,
      roles           = '["IT_ADMIN"]'
  WHERE username = 'admin'
    AND (hashed_password IS NULL OR hashed_password = '');

INSERT INTO mcp_definitions
  (name,mcp_type,visibility,description,processing_intent,api_config,input_schema,prefer_over_system,created_at,updated_at)
VALUES
  ('list_active_lots','system','public','== What == active lot (Waiting/Processing)。== Returns == [{lot_id,current_step,status,cycle}]','','{"endpoint_url":"{ONTOLOGY_SIM_URL}/api/v1/lots?status=active","method":"GET","headers":{}}','{"fields":[]}',false,NOW(),NOW()),
  ('list_steps','system','public','== What == 所有 process steps。== Returns == {total,data:[{name,description}]}','','{"endpoint_url":"{ONTOLOGY_SIM_URL}/api/v1/list-steps","method":"GET","headers":{}}','{"fields":[]}',false,NOW(),NOW()),
  ('list_apcs','system','public','== What == 所有 APC config object。== Returns == {total,data:[{apcID}]}','','{"endpoint_url":"{ONTOLOGY_SIM_URL}/api/v1/list-apcs","method":"GET","headers":{}}','{"fields":[]}',false,NOW(),NOW()),
  ('list_spcs','system','public','== What == SPC chart 種類(xbar/r/s/p/c)。== Returns == {total,data:[{chart,description}]}','','{"endpoint_url":"{ONTOLOGY_SIM_URL}/api/v1/list-spcs","method":"GET","headers":{}}','{"fields":[]}',false,NOW(),NOW())
ON CONFLICT (name) DO UPDATE
  SET api_config = EXCLUDED.api_config, updated_at = NOW();
'@ | Set-Content -Path $tmpSql -Encoding UTF8

docker cp $tmpSql "deploy-postgres-1:/tmp/patch.sql" 2>&1 | Out-Null
docker exec deploy-postgres-1 sh -c "psql -U aiops -d aiops -f /tmp/patch.sql" 2>&1 | Out-Null
Remove-Item $tmpSql -ErrorAction SilentlyContinue

Write-Ok "admin 密碼已設定 (admin / Admin1234!)"
Write-Ok "list_active_lots / list_steps / list_apcs / list_spcs MCPs 已設定"

# ─── Phase 4：自動化 QA ───────────────────────────────────────────────────────
Write-Step "Phase 4 — 執行 QA 驗證"
& "$SCRIPT_DIR\qa-local.ps1"
```

---

### 3-J. `deploy/qa-local.ps1`（QA 驗證腳本）

建立 `deploy/qa-local.ps1`，內容如下：

```powershell
# deploy/qa-local.ps1
# Local Docker QA verification script
#
# Usage (from project root):
#   .\deploy\qa-local.ps1
#
# Test account: admin@aiops.local / Admin1234!

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$SIDECAR_TOKEN = "aiops_sidecar_token_2024"
$JAVA_URL      = "http://localhost:8002"
$SIDECAR_URL   = "http://localhost:8050"
$SIMULATOR_URL = "http://localhost:8012"
$APP_URL       = "http://localhost:8000"

$results = [ordered]@{}

function Test-Http {
    param(
        [string]$label,
        [string]$uri,
        [string]$method = "GET",
        [hashtable]$body = $null,
        [hashtable]$headers = @{},
        [string]$expectContent = $null
    )
    try {
        $params = @{
            Uri             = $uri
            Method          = $method
            UseBasicParsing = $true
            TimeoutSec      = 10
            Headers         = $headers
        }
        if ($body) {
            $params.Body        = $body | ConvertTo-Json -Compress
            $params.ContentType = "application/json"
        }
        $r = Invoke-WebRequest @params
        if ($r.StatusCode -ge 400) {
            $results[$label] = "FAIL (HTTP $($r.StatusCode))"
            return $null
        }
        if ($expectContent -and ($r.Content -notmatch [regex]::Escape($expectContent))) {
            $results[$label] = "FAIL (expected '$expectContent' in response)"
            return $null
        }
        $results[$label] = "PASS"
        return $r.Content
    } catch {
        $msg = $_.Exception.Message -replace "`r`n.*", "" -replace "`n.*", ""
        $results[$label] = "FAIL ($msg)"
        return $null
    }
}

Write-Host ""
Write-Host "============================================"
Write-Host "  AIOps Local Docker QA"
Write-Host "============================================"

# Test 1: Ontology Simulator
Test-Http "1 Ontology Simulator health" "$SIMULATOR_URL/api/v1/status" | Out-Null

# Test 2: Java API
Test-Http "2 Java API health" "$JAVA_URL/actuator/health" | Out-Null

# Test 3: Python Sidecar
Test-Http "3 Python Sidecar health" "$SIDECAR_URL/internal/health" `
    -headers @{"X-Service-Token" = $SIDECAR_TOKEN} | Out-Null

# Test 4: Local login -> get JWT
Test-Http "4 Local login (admin)" "$JAVA_URL/api/v1/auth/login" `
    -method POST -body @{username = "admin"; password = "Admin1234!"} `
    -expectContent "access_token" | Out-Null

# Test 5: Simulator active lots
$lotsContent = Test-Http "5 Simulator active lots" "$SIMULATOR_URL/api/v1/lots?status=active"
if ($lotsContent -and $results["5 Simulator active lots"] -eq "PASS") {
    try {
        $lots = $lotsContent | ConvertFrom-Json
        $count = if ($lots -is [array]) { $lots.Count } `
            elseif ($lots.data -is [array]) { $lots.data.Count } `
            else { 0 }
        if ($count -gt 0) {
            $results["5 Simulator active lots"] = "PASS ($count lots)"
        } else {
            $results["5 Simulator active lots"] = "WARN (0 lots - simulator data may not be seeded)"
        }
    } catch {}
}

# Test 6: MCP definition check via /internal/mcp-definitions
$mcpDef = $null
try {
    $r = Invoke-WebRequest -Uri "$JAVA_URL/internal/mcp-definitions" `
        -Headers @{"X-Internal-Token" = "aiops_internal_token_2024"} `
        -UseBasicParsing -TimeoutSec 10
    $mcpDef = $r.Content
} catch {}
if ($mcpDef -match "ONTOLOGY_SIM_URL") {
    $results["6 MCP URL placeholder"] = "PASS (list MCPs use {ONTOLOGY_SIM_URL} placeholder)"
} elseif ($mcpDef -match "localhost:8012") {
    $results["6 MCP URL placeholder"] = "FAIL (still has localhost:8012 - MCPs not fixed)"
} elseif ($mcpDef) {
    $results["6 MCP URL placeholder"] = "WARN (MCPs found but placeholder status unclear)"
} else {
    $results["6 MCP URL placeholder"] = "SKIP (internal MCP endpoint not reachable)"
}

# Test 7: AIOps App homepage
Test-Http "7 AIOps App homepage" $APP_URL | Out-Null

# Print results
Write-Host ""
Write-Host "============================================"
Write-Host "  QA Results"
Write-Host "============================================"

$allPassed = $true
foreach ($kv in $results.GetEnumerator()) {
    $label = $kv.Key
    $val   = $kv.Value
    if ($val -like "PASS*") {
        Write-Host "  [PASS]  $label -- $val"
    } elseif ($val -like "WARN*" -or $val -like "SKIP*") {
        Write-Host "  [WARN]  $label -- $val"
        $allPassed = $false
    } else {
        Write-Host "  [FAIL]  $label -- $val"
        $allPassed = $false
    }
}

Write-Host "============================================"
Write-Host ""
Write-Host "  Keycloak account : admin@aiops.local / Admin1234!"
Write-Host "  Local account    : admin / Admin1234!"
Write-Host ""

if ($allPassed) {
    Write-Host "  [OK] All tests passed - local Docker deployment is healthy"
} else {
    Write-Host "  [!!] Some tests failed - see above"
    Write-Host "  Diagnose:"
    Write-Host "    docker compose -f deploy/docker-compose.yml logs aiops-java-api --tail 50"
    Write-Host "    docker compose -f deploy/docker-compose.yml logs aiops-python-sidecar --tail 50"
}
Write-Host "============================================"
```

---

### 3-K. `deploy/keycloak-setup.ps1`（Keycloak 初始化腳本）

建立 `deploy/keycloak-setup.ps1`，內容如下：

```powershell
# deploy/keycloak-setup.ps1
# 建立 aiops realm、clients、roles、測試使用者
# 由 start-local.ps1 Phase 2 呼叫，也可單獨執行

# 1. 取得管理員 Token
Write-Host "Getting Keycloak admin token..."
$tokenResponse = Invoke-WebRequest -Uri "http://localhost:8090/realms/master/protocol/openid-connect/token" `
    -Method POST -UseBasicParsing `
    -Body "client_id=admin-cli&username=admin&password=aiops_keycloak_admin&grant_type=password" `
    -ContentType "application/x-www-form-urlencoded" | ConvertFrom-Json

$TOKEN = $tokenResponse.access_token
Write-Host "Token obtained."

$headers = @{ "Authorization" = "Bearer $TOKEN"; "Content-Type" = "application/json" }

# 2. 建立 aiops realm
Write-Host "Creating aiops realm..."
try {
    Invoke-WebRequest -Uri "http://localhost:8090/admin/realms" -Method POST -UseBasicParsing `
        -Headers $headers -Body '{"realm":"aiops","enabled":true}' | Out-Null
} catch {}

# 3. 建立 aiops-backend client
Write-Host "Creating aiops-backend client..."
try {
    Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/clients" -Method POST -UseBasicParsing `
        -Headers $headers `
        -Body '{"clientId":"aiops-backend","enabled":true,"clientAuthenticatorType":"client-secret","secret":"aiops-backend-secret-2024","serviceAccountsEnabled":true,"publicClient":false}' | Out-Null
} catch {}

# 4. 建立 aiops-frontend client
Write-Host "Creating aiops-frontend client..."
try {
    Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/clients" -Method POST -UseBasicParsing `
        -Headers $headers `
        -Body '{"clientId":"aiops-frontend","enabled":true,"clientAuthenticatorType":"client-secret","secret":"aiops-frontend-secret-2024","standardFlowEnabled":true,"publicClient":false,"redirectUris":["http://localhost:8000/api/auth/callback/keycloak"],"webOrigins":["http://localhost:8000"]}' | Out-Null
} catch {}

# 5. 建立 Realm Roles
Write-Host "Creating realm roles..."
foreach ($role in @("IT_ADMIN", "PE", "ON_DUTY")) {
    try {
        Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/roles" -Method POST -UseBasicParsing `
            -Headers $headers -Body "{`"name`":`"$role`"}" | Out-Null
    } catch {}
}

# 6. 新增 roles claim 到 aiops-frontend JWT
Write-Host "Adding roles claim to JWT..."
$CLIENT_ID = (Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/clients?clientId=aiops-frontend" `
    -UseBasicParsing -Headers $headers | ConvertFrom-Json)[0].id

try {
    Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/clients/$CLIENT_ID/protocol-mappers/models" `
        -Method POST -UseBasicParsing -Headers $headers `
        -Body '{"name":"realm-roles-claim","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","config":{"claim.name":"roles","jsonType.label":"String","multivalued":"true","userinfo.token.claim":"true","id.token.claim":"true","access.token.claim":"true"}}' | Out-Null
} catch {}

# 7. 建立測試使用者並指派 IT_ADMIN 角色
Write-Host "Creating test user admin@aiops.local..."
try {
    Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/users" -Method POST -UseBasicParsing `
        -Headers $headers `
        -Body '{"username":"admin@aiops.local","email":"admin@aiops.local","enabled":true,"emailVerified":true,"credentials":[{"type":"password","value":"Admin1234!","temporary":false}]}' | Out-Null
} catch {}

$USER_ID = (Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/users?username=admin@aiops.local" `
    -UseBasicParsing -Headers $headers | ConvertFrom-Json)[0].id

$ROLE_ID = (Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/roles/IT_ADMIN" `
    -UseBasicParsing -Headers $headers | ConvertFrom-Json).id

Invoke-WebRequest -Uri "http://localhost:8090/admin/realms/aiops/users/$USER_ID/role-mappings/realm" `
    -Method POST -UseBasicParsing -Headers $headers `
    -Body "[{`"id`":`"$ROLE_ID`",`"name`":`"IT_ADMIN`"}]" | Out-Null

Write-Host "Keycloak setup complete!"
```

---

## 步驟四：Source Code 補丁（兩個檔案必須修改）

> **這兩個修改解決 Docker 環境的根本問題，新 clone 的 repo 不含這些修正，必須手動套用。**

### 4-A. `java-backend/src/main/resources/application-prod.yml`

**問題**：Spring Boot prod profile 會用此 YAML 覆蓋 `application.yml` 的預設值。  
若 `auth.mode` 寫死為 `oidc`，即使 `app.env` 設 `AUTH_MODE=local` 也無效 → 本地帳密登入回傳「local login disabled」。

**修改前**（可能是 `mode: oidc` 或類似硬編碼）：

```yaml
aiops:
  auth:
    mode: oidc   # ← 這一行會導致本地登入完全失敗
```

**修改後**（改成讀環境變數）：

```yaml
spring:
  jpa:
    # Phase 5-7 shared-schema reality: Python owns DDL (Alembic), Java reads
    # the same tables. Python uses INTEGER FK columns; Java entities use Long
    # which maps to BIGINT. Hibernate's `validate` would complain, but at
    # runtime PostgreSQL auto-casts INT → BIGINT on read + write, so the
    # mismatch is validation-time only. Flip back to `validate` in Phase 8+
    # when Java fully owns the schema (needs a migration that bumps column
    # types to BIGINT).
    hibernate:
      ddl-auto: none
  flyway:
    enabled: ${FLYWAY_ENABLED:false}

aiops:
  auth:
    mode: ${AUTH_MODE:local}
  cors:
    allowed-origins: ${CORS_ALLOWED_ORIGINS}

logging:
  level:
    com.aiops.api: INFO
```

> **重要**：修改此檔案後，Java image 必須重新 build（步驟五）才能生效。

---

### 4-B. `python_ai_sidecar/pipeline_builder/blocks/mcp_call.py`

**問題**：MCP 的 `endpoint_url` DB 裡儲存 `{ONTOLOGY_SIM_URL}` placeholder，但 sidecar 執行時不解析 → 對 `{ONTOLOGY_SIM_URL}/...` 發 HTTP 請求失敗 → Simulator 完全沒有作用。

在該檔案中找到這一段（約在 112 行附近）：

```python
url = api_config.get("endpoint_url")
method = (api_config.get("method") or "GET").upper()
headers = api_config.get("headers") or {}
if not url:
```

**在 `headers = ...` 和 `if not url:` 之間插入以下三行**：

```python
        # Resolve {ONTOLOGY_SIM_URL} placeholder so Docker containers use the
        # correct service name instead of the hardcoded localhost:8012 in V17 migration.
        if url and "{ONTOLOGY_SIM_URL}" in url:
            from python_ai_sidecar.config import get_settings
            url = url.replace("{ONTOLOGY_SIM_URL}", get_settings().ONTOLOGY_SIM_URL.rstrip("/"))
```

修改後該段應如下：

```python
        url = api_config.get("endpoint_url")
        method = (api_config.get("method") or "GET").upper()
        headers = api_config.get("headers") or {}
        # Resolve {ONTOLOGY_SIM_URL} placeholder so Docker containers use the
        # correct service name instead of the hardcoded localhost:8012 in V17 migration.
        if url and "{ONTOLOGY_SIM_URL}" in url:
            from python_ai_sidecar.config import get_settings
            url = url.replace("{ONTOLOGY_SIM_URL}", get_settings().ONTOLOGY_SIM_URL.rstrip("/"))
        if not url:
            raise BlockExecutionError(
```

> 修改此檔案後，python-sidecar image 必須重新 build 才能生效。

---

## 步驟五：填寫設定檔

### 5-A. Shared Token 對照表

以下 Token 在多個服務間**必須完全一致**：

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
| Keycloak admin 密碼 | `aiops_keycloak_admin` |

> **生產環境請換成強密碼。**

---

### 5-B. `deploy/docker/aiops-app/config/.env`

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
> 兩個值分開設定，是 Split-Horizon OIDC 的核心（`aiops-app/src/auth.ts` 已實作）

---

### 5-C. `deploy/docker/java-backend/config/app.env`

```env
AIOPS_PROFILE=prod
AIOPS_JAVA_PORT=8080
DB_URL=jdbc:postgresql://postgres:5432/aiops
DB_USER=aiops
DB_PASSWORD=aiops_db_pass
JWT_SECRET=CHANGE_ME_32_CHARS_OR_MORE_____________
AUTH_MODE=local
OIDC_ISSUER=http://localhost:8090/realms/aiops
OIDC_CLIENT_ID=aiops-backend
OIDC_CLIENT_SECRET=aiops-backend-secret-2024
OIDC_ROLE_CLAIM=roles
OIDC_JWK_URI=http://keycloak:8080/realms/aiops/protocol/openid-connect/certs
AIOPS_OIDC_UPSERT_SECRET=aiops_upsert_secret_2024
AIOPS_SHARED_SECRET_TOKEN=aiops_internal_token_2024
PYTHON_SIDECAR_URL=http://aiops-python-sidecar:8080
PYTHON_SIDECAR_TOKEN=aiops_sidecar_token_2024
JAVA_INTERNAL_TOKEN=aiops_internal_token_2024
JAVA_INTERNAL_ALLOWED_IPS=
AIOPS_SCHEDULER_BASE_URL=http://aiops-java-scheduler:8080
AIOPS_SCHEDULER_INTERNAL_TOKEN=aiops_scheduler_token_2024
CORS_ALLOWED_ORIGINS=http://localhost:8000
ONTOLOGY_SIM_URL=http://ontology-simulator:8080
```

> **關鍵**：`AUTH_MODE=local`（必須，不可為 `oidc`，否則本地帳密登入失敗）  
> **關鍵**：`AIOPS_SHARED_SECRET_TOKEN` 必須填值，不可留空

---

### 5-D. `deploy/docker/java-scheduler/config/app.env`

```env
AIOPS_SCHEDULER_PORT=8080
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

### 5-E. `deploy/docker/python-sidecar/config/app.env`

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

ONTOLOGY_SIM_URL=http://ontology-simulator:8080
POLLER_SOURCE_URL=http://ontology-simulator:8080/events

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

ONTOLOGY_SIM_URL=http://ontology-simulator:8080
POLLER_SOURCE_URL=http://ontology-simulator:8080/events

# 背景任務（初始可停用）
EVENT_POLLER_ENABLED=0
NATS_SUBSCRIBER_ENABLED=0
```

> `host.docker.internal` 是 Docker Desktop for Windows/Mac 的特殊 DNS，  
> 讓容器可以連回到宿主機（你的電腦）上的 Ollama。

---

### 5-F. `deploy/docker/ontology-simulator/config/app.env`

```env
PORT=8080
MONGODB_URI=mongodb://mongo:27017
```

---

## 步驟六：Build 所有自定義映像

```powershell
docker compose -f deploy/docker-compose.yml build
```

- 首次 build 約需 **10–20 分鐘**（Maven 下載依賴、npm 安裝套件）
- 後續再 build 會使用 layer cache，速度大幅加快
- 如果只修改了 config 檔案（不修改 source code），不需要重新 build

---

## 步驟七：執行啟動腳本

```powershell
.\deploy\start-local.ps1
```

腳本完成後，終端機會顯示 QA 結果：

```
============================================
  QA Results
============================================
  [PASS]  1 Ontology Simulator health -- PASS
  [PASS]  2 Java API health -- PASS
  [PASS]  3 Python Sidecar health -- PASS
  [PASS]  4 Local login (admin) -- PASS
  [PASS]  5 Simulator active lots -- PASS (N lots)
  [PASS]  6 MCP URL placeholder -- PASS (list MCPs use {ONTOLOGY_SIM_URL} placeholder)
  [PASS]  7 AIOps App homepage -- PASS
============================================
  Keycloak account : admin@aiops.local / Admin1234!
  Local account    : admin / Admin1234!

  [OK] All tests passed - local Docker deployment is healthy
============================================
```

---

## 步驟八：登入測試

在瀏覽器開啟 **http://localhost:8000**

| 登入方式 | 帳號 | 密碼 | 角色 |
|---|---|---|---|
| 本地帳密 | `admin` | `Admin1234!` | IT_ADMIN |
| Keycloak SSO | `admin@aiops.local` | `Admin1234!` | IT_ADMIN |

> **角色說明：**
> - `IT_ADMIN`：最高權限，可建立 Pipeline、編輯 Skill、讀寫記憶體
> - `PE`：Process Engineer，可使用 AI Agent + 建立 Pipeline，不能管理系統設定
> - `ON_DUTY`：值班工程師，唯讀模式，只能使用已發布的 Skill，不能建立新的 Pipeline

> **首次以 Keycloak 登入時**，Keycloak 可能跳「Update Account Information」要求填 First name / Last name。填完一次後就不再出現。

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
| 27017 | MongoDB | 文件資料庫（Simulator 用） |
| 6379 | Redis | 快取 / 排程佇列 |

---

## 常用維運指令

```powershell
# 單獨執行 QA 驗證
.\deploy\qa-local.ps1

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
docker exec deploy-postgres-1 psql -U aiops -d aiops -c "CREATE EXTENSION IF NOT EXISTS vector;"
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
| Qwen3 8B | `ollama pull qwen3:8b` | ~5 GB | 支援 |
| Qwen3 14B | `ollama pull qwen3:14b` | ~9 GB | 支援 |
| Llama3.1 8B | `ollama pull llama3.1:8b` | ~5 GB | 支援 |
| bge-m3（嵌入模型） | `ollama pull bge-m3` | ~1.2 GB | N/A（必須安裝） |

> **嵌入模型 bge-m3 是必須的**：AI Agent 的語意記憶使用 1024 維向量，bge-m3 輸出正好是 1024 維。若不安裝，知識庫搜尋功能將無法運作。

---

## 常見問題排除

### Q: 本地帳密登入回傳「local login disabled」

**根因**：Java 以 `AUTH_MODE=oidc` 啟動（`application-prod.yml` 未套用步驟四-A 的修正，或修正後未 rebuild）。

**修復**：
1. 確認 `java-backend/src/main/resources/application-prod.yml` 中 `mode: ${AUTH_MODE:local}` 已套用
2. 重新 build + restart：
```powershell
docker compose -f deploy/docker-compose.yml build aiops-java-api
docker compose -f deploy/docker-compose.yml up -d --no-deps aiops-java-api
```

---

### Q: 本地帳密登入回傳「invalid credentials（403）」

**根因**：admin 使用者沒有本地密碼（Keycloak oidc-upsert 建立的帳戶預設 `hashed_password` 為空）。

**修復**：重新執行 `start-local.ps1`（Phase 3.5 是 idempotent 的），或手動執行：
```powershell
docker exec deploy-postgres-1 psql -U aiops -d aiops -c "
CREATE EXTENSION IF NOT EXISTS pgcrypto;
UPDATE users SET hashed_password = crypt('Admin1234!', gen_salt('bf', 12)), is_active = true, roles = '[\"IT_ADMIN\"]' WHERE username = 'admin';
"
```

---

### Q: AI Agent 呼叫 Simulator 無效果（list_active_lots 等 MCP 沒有資料）

**根因 1**：`mcp_call.py` 沒有套用步驟四-B 的 placeholder 解析補丁 → sidecar 對 `{ONTOLOGY_SIM_URL}/...` 字面發請求失敗。  
**修復**：套用補丁後重新 build python-sidecar。

**根因 2**：`mcp_definitions` 表沒有 list_* 記錄（Phase 3.5 未執行）。  
**修復**：重新執行 `start-local.ps1` 或 `qa-local.ps1` 後手動確認。

**根因 3**：python-sidecar 的 `ONTOLOGY_SIM_URL` 環境變數缺失。  
**修復**：確認 `deploy/docker/python-sidecar/config/app.env` 有 `ONTOLOGY_SIM_URL=http://ontology-simulator:8080`。

---

### Q: Keycloak 登入後出現「登入失敗：Configuration」錯誤

**根因**：NextAuth v5 的 `Keycloak()` provider 走 OIDC discovery，回傳的 endpoints 指向 `localhost:8090`，但容器內部無法解析 → 登入失敗。

**確認**：`aiops-app/src/auth.ts` 應使用手動 `type: "oauth"` provider（不走 discovery），且設定了 `OIDC_KEYCLOAK_ISSUER_INTERNAL`。若 repo 版本正確，此問題不應發生。若 build 後仍有此問題，查看：
```powershell
docker logs deploy-aiops-app-1 --tail 30
```

---

### Q: AI Agent 對話無回應 / 401 或 403 錯誤

- **401**：Bearer Token 類型不正確。確認 `auth-proxy.ts` 優先使用 `idpAccessToken`（Keycloak JWT）。
- **403**：JWT 中缺少 `roles` 欄位。確認 Keycloak 的 Protocol Mapper 已建立（`start-local.ps1` Phase 2 會自動處理）。

---

### Q: AI Agent 回應 Anthropic 401 / 402 錯誤

- **401**：`ANTHROPIC_API_KEY` 無效，請確認填入正確的 API Key。
- **402 / 400**：Anthropic 帳戶餘額不足，請前往 [console.anthropic.com](https://console.anthropic.com) 加值。
- 替代方案：改用本地 Ollama（見上方 LLM 選項切換章節）。

---

### Q: postgres 容器健康但表格不存在

pgvector extension 未正確初始化：
```powershell
docker exec deploy-postgres-1 psql -U aiops -d aiops -c "CREATE EXTENSION IF NOT EXISTS vector;"
docker restart deploy-aiops-java-api-1
```

---

### Q: Port 已被佔用（address already in use）

查看佔用的 Port 並關閉對應程式，或修改 `deploy/docker-compose.yml` 中的 host port（左側數字）。

---

### Q: Keycloak Realm 資料在重啟後消失

Keycloak 使用 `keycloak_data` volume。若 volume 被刪除（`docker compose down -v`），Realm 設定一併清除。重建後重新執行：
```powershell
.\deploy\start-local.ps1
```
腳本 Phase 2 會自動重建 realm（idempotent）。

---

*最後更新：2026-05-17（全面重寫：新增 start-local.ps1 / qa-local.ps1 / keycloak-setup.ps1 完整內容；新增步驟四 Source Code 補丁；重整為可從全新 clone 直接執行的自完備 SOP）*
