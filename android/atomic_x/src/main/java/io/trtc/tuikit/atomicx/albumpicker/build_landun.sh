#!/bin/bash
#
# AlbumPicker 业务层打包脚本（不依赖本地 Maven 仓库）
#
# 用法:
#   ./build_landun.sh <albumpickercore.aar 路径> <版本号>
#
# 示例:
#   ./build_landun.sh /path/to/albumpickercore.aar 1.0.0.0
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANDROID_DIR="$SCRIPT_DIR/../../../../../../../../.."
APP_DIR="$ANDROID_DIR/application"
SETTINGS_GRADLE="$APP_DIR/settings.gradle"
BIZ_BUILD_GRADLE="$SCRIPT_DIR/build.gradle"

# ========== 参数校验 ==========
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "用法: $0 <albumpickercore.aar 路径> <版本号>"
    echo "示例: $0 /path/to/albumpickercore.aar 1.0.0.0"
    exit 1
fi

CORE_AAR_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
if [ ! -f "$CORE_AAR_PATH" ]; then
    echo "错误: 找不到文件 $CORE_AAR_PATH"
    exit 1
fi

VERSION="$2"
echo "albumpickercore AAR: $CORE_AAR_PATH"
echo "版本号: $VERSION"

# ========== 准备 AAR 临时目录 ==========
LIBS_DIR="$APP_DIR/albumpicker_libs"
mkdir -p "$LIBS_DIR"
cp "$CORE_AAR_PATH" "$LIBS_DIR/albumpickercore.aar"

# ========== 确保 local.properties 存在（CI 环境可能没有）==========
LOCAL_PROPS="$APP_DIR/local.properties"
LOCAL_PROPS_CREATED=false
if [ ! -f "$LOCAL_PROPS" ]; then
    echo "sdk.dir=${ANDROID_HOME:-/opt/android/sdk}" > "$LOCAL_PROPS"
    LOCAL_PROPS_CREATED=true
fi

# ========== 备份文件 ==========
cp "$SETTINGS_GRADLE" "$SETTINGS_GRADLE.bak"
cp "$BIZ_BUILD_GRADLE" "$BIZ_BUILD_GRADLE.bak"

restore() {
    mv "$SETTINGS_GRADLE.bak" "$SETTINGS_GRADLE"
    mv "$BIZ_BUILD_GRADLE.bak" "$BIZ_BUILD_GRADLE"
    rm -rf "$LIBS_DIR"
    if [ "$LOCAL_PROPS_CREATED" = true ]; then
        rm -f "$LOCAL_PROPS"
    fi
}
trap restore EXIT

# ========== 修改 settings.gradle ==========
# 将 FAIL_ON_PROJECT_REPOS 改为 PREFER_SETTINGS，兼容 CI 环境的 init.gradle
sed -i "s/FAIL_ON_PROJECT_REPOS/PREFER_SETTINGS/" "$SETTINGS_GRADLE"
sed -i "/flatDir {/,/}/s|dirs.*|dirs 'app/libs', 'albumpicker_libs'|" "$SETTINGS_GRADLE"

# 追加 albumpicker 模块声明
cat >> "$SETTINGS_GRADLE" << 'SETTINGS_EOF'

include ':albumpicker'
project(':albumpicker').projectDir = new File(settingsDir, "../atomic_x/src/main/java/io/trtc/tuikit/atomicx/albumpicker")
SETTINGS_EOF

# ========== 修改 build.gradle: 更新版本号 + 替换依赖为本地 AAR ==========
sed -i "s|def albumpickerVersion = \".*\"|def albumpickerVersion = \"${VERSION}\"|" "$BIZ_BUILD_GRADLE"
sed -i "s|api \"io.trtc.uikit:albumpickercore:.*\"|api(name: 'albumpickercore', ext: 'aar')\n    implementation 'com.google.android.material:material:1.12.0'\n    implementation 'com.github.bumptech.glide:glide:4.12.0'\n    api 'androidx.lifecycle:lifecycle-viewmodel-ktx:2.6.2'|" "$BIZ_BUILD_GRADLE"

# ========== 打包 ==========
echo ""
echo "📦 打包 albumpicker..."
cd "$APP_DIR"
./gradlew clean :albumpicker:assembleRelease \
    -PbuildEngineSource=false \
    -PbuildAtomicxCoreSource=false \
    --quiet

# ========== 输出结果 ==========
OUTPUT_AAR="$APP_DIR/build/albumpicker/outputs/aar/albumpicker-release.aar"
if [ -f "$OUTPUT_AAR" ]; then
    FINAL_AAR="$SCRIPT_DIR/albumpicker-release.aar"
    cp "$OUTPUT_AAR" "$FINAL_AAR"
    echo ""
    echo "✅ 打包成功!"
    echo "  产物: $FINAL_AAR ($(du -h "$FINAL_AAR" | cut -f1))"
else
    echo ""
    echo "❌ 错误: 未找到产物，请检查构建日志"
    exit 1
fi
