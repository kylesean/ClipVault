# ClipVault 项目管理命令
.PHONY: dev stop build apk deploy update-douyin setup

# ===== 本地开发 =====

## 启动后端服务（开发模式）
dev:
	@echo "启动抖音解析服务 (port 8080)..."
	cd backend/douyin_api && .venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8080 &
	@echo "启动主解析服务 (port 8000)..."
	cd backend && uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

## 停止所有后端服务
stop:
	pkill -f "uvicorn app.main:app" || true

## 初始化环境（新机器首次运行）
setup:
	@echo "=== 初始化 Git Submodule ==="
	git submodule update --init --recursive
	@echo "=== 安装主服务依赖 ==="
	cd backend && uv venv && uv pip install -r requirements.txt
	@echo "=== 安装抖音解析服务依赖 ==="
	cd backend/douyin_api && uv venv --python 3.11 .venv && uv pip install --python .venv/bin/python -r requirements.txt
	@echo "=== 安装 Flutter 依赖 ==="
	flutter pub get
	@echo "✅ 环境初始化完成"

# ===== 构建 =====

## 构建 Android APK
apk:
	flutter build apk --release

## 构建 Android App Bundle (Play Store)
aab:
	flutter build appbundle --release

## Docker 构建后端
build:
	docker compose build

# ===== 部署 =====

## Docker 一键部署后端
deploy:
	docker compose up -d

## 查看服务日志
logs:
	docker compose logs -f

## 停止 Docker 服务
down:
	docker compose down

# ===== 维护 =====

## 更新抖音解析引擎（拉取上游最新代码）
update-douyin:
	cd backend/douyin_api && git pull origin main
	@echo "✅ 已更新，记得重启服务: make stop && make dev"

## 更新 Flutter 依赖
upgrade:
	flutter pub upgrade
