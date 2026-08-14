# ClipVault 项目管理命令
.PHONY: dev stop build apk setup update-douyin-core

# 可通过环境变量覆盖，默认 8000
PORT ?= 8000

# ===== 本地开发 =====

## 启动后端服务（开发模式，抖音核心算法已内嵌，单进程即可）
dev:
	cd backend && CLIPVAULT_PORT=$(PORT) uv run uvicorn app.main:app --host 0.0.0.0 --port $(PORT) --reload

## 停止所有后端服务
stop:
	pkill -f "uvicorn app.main:app" || true

## 初始化环境（新机器首次运行）
setup:
	@echo "=== 安装主服务依赖 ==="
	cd backend && uv venv && uv pip install -r requirements.txt
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

## 同步抖音核心算法（拉取上游 abogus.py 等文件，抖音改版后执行）
update-douyin-core:
	python3 scripts/sync_douyin_core.py

## 更新 Flutter 依赖
upgrade:
	flutter pub upgrade
