# ClipVault 项目管理命令（纯端版，无服务端）
.PHONY: setup test analyze apk aab ipa run upgrade clean

# ===== 本地开发 =====

## 初始化环境（新机器首次运行）
setup:
	flutter pub get

## 运行 App（连设备或模拟器）
run:
	flutter run

# ===== 质量门禁 =====

## 静态分析
analyze:
	flutter analyze

## 单元测试
test:
	flutter test

# ===== 构建（自用侧载，无需签名配置） =====

## 构建 Android APK
apk:
	flutter build apk --release

## 构建 Android App Bundle
aab:
	flutter build appbundle --release

## 构建 iOS（免签，侧载用，macOS only）
ipa:
	flutter build ios --release --no-codesign

# ===== 维护 =====

## 跟版：抖音改版（a_bogus 失效）后，对照上游同步签名参数
## 上游：https://github.com/Evil0ctal/Douyin_TikTok_Download_API
## 步骤：1) 跑 flutter test test/abogus_test.dart 看哪条向量挂了
##       2) 用 test 里 debugParamsCode/debugMethodCode 探针定位
##       3) 更新 lib/features/decode/abogus.dart + 补向量
sync-sign:
	@echo "见 Makefile 注释：对照上游更新 abogus.dart，然后 flutter test"

## 更新 Flutter 依赖
upgrade:
	flutter pub upgrade

## 清理构建产物
clean:
	flutter clean
