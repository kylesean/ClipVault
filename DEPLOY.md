# ClipVault 后端部署指南

## 服务器要求

- Linux (Ubuntu 22.04+ / Debian 12+ 推荐)
- 1GB+ RAM
- Docker + Docker Compose（推荐）或 Python 3.11+
- 可选：Nginx 反向代理 + SSL

---

## 方案一：Docker 部署（推荐）

### 1. 安装 Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# 重新登录生效
```

### 2. 克隆项目

```bash
git clone --recurse-submodules https://github.com/kylesean/ClipVault.git
cd ClipVault
```

### 3. 配置抖音 Cookie

编辑 `backend/douyin_api/crawlers/douyin/web/config.yaml`，找到 `Cookie:` 行替换为你自己的：

```yaml
TokenManager:
  douyin:
    headers:
      Cookie: "ttwid=xxx; s_v_web_id=xxx; __ac_nonce=xxx; ..."
```

> 获取方式：浏览器打开 douyin.com → F12 → Network → 复制任意请求的 Cookie 头

### 4. 启动服务

```bash
docker compose up -d
```

验证：

```bash
curl http://localhost:8000/api/health
# {"status":"ok","service":"clipvault-parse"}
```

### 5. 更新

```bash
git pull
git submodule update --remote backend/douyin_api
docker compose up -d --build
```

---

## 方案二：手动部署（无 Docker）

### 1. 安装 uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
```

### 2. 克隆并初始化

```bash
git clone --recurse-submodules https://github.com/kylesean/ClipVault.git
cd ClipVault
make setup
```

### 3. 配置 Cookie

同方案一第 3 步。

### 4. 创建 Systemd 服务

```bash
sudo tee /etc/systemd/system/clipvault.service << 'EOF'
[Unit]
Description=ClipVault Parse Service
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/ClipVault/backend
ExecStart=/opt/ClipVault/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5
Environment=DOUYIN_API_URL=http://127.0.0.1:8080

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/clipvault-douyin.service << 'EOF'
[Unit]
Description=ClipVault Douyin Parse Engine
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/ClipVault/backend/douyin_api
ExecStart=/opt/ClipVault/backend/douyin_api/.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### 5. 启动

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now clipvault-douyin
sudo systemctl enable --now clipvault
```

查看日志：

```bash
journalctl -u clipvault -f
```

---

## Nginx 反向代理（可选）

```nginx
server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }
}
```

加 SSL（Let's Encrypt）：

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d api.yourdomain.com
```

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLIPVAULT_PORT` | 8000 | 主服务端口 |
| `DOUYIN_API_PORT` | 8080 | 抖音解析引擎端口 |
| `DOUYIN_API_URL` | http://localhost:8080 | 主服务连接抖音引擎的地址 |
| `COOKIE_REFRESH_INTERVAL` | 43200 | Cookie 自动刷新间隔（秒，默认12h） |
| `CLIPVAULT_CORS_ORIGINS` | * | 允许的跨域来源 |

---

## 客户端连接

App 中修改后端地址（`lib/core/constants/app_constants.dart`）：

```dart
static const String parseApiBaseUrl = 'http://你的服务器IP:8000';
```

如果加了 Nginx + SSL：

```dart
static const String parseApiBaseUrl = 'https://api.yourdomain.com';
```

---

## 日常维护

```bash
# 查看服务状态
docker compose ps          # Docker 方式
systemctl status clipvault # Systemd 方式

# 查看日志
docker compose logs -f
journalctl -u clipvault -f

# 刷新 Cookie（解析失败时）
curl -X POST http://localhost:8000/api/cookies/douyin/refresh

# 更新抖音解析引擎
make update-douyin
```

---

## 故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| 解析返回空/403 | Cookie 过期 | 刷新 Cookie |
| 连接超时 | 防火墙未放行端口 | `ufw allow 8000` |
| 抖音解析失败但 YouTube 正常 | 抖音引擎未启动 | 检查 8080 端口服务 |
| 内存不足 OOM | 资源限制太小 | 调高 docker-compose 内存限制 |
