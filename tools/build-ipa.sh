#!/usr/bin/env bash
# 尾翼控制器 — 归档并导出 IPA（macOS / GitHub Actions macOS runner 通用）
#
# 用法：
#   bash tools/build-ipa.sh              # 默认：免签名 IPA
#   bash tools/build-ipa.sh --unsigned   # 强制免签名
#   bash tools/build-ipa.sh --signed     # 签名 IPA（需先导入证书与描述文件）
#
# 签名模式需要的环境变量：
#   IOS_TEAM_ID           Apple Developer Team ID，例如 A1B2C3D4E5
#   IOS_PROFILE_UUID      .mobileprovision 内部的 UUID
#   IOS_EXPORT_METHOD     ad-hoc | development | app-store | enterprise（默认 ad-hoc）
#   IOS_SIGNING_IDENTITY  可选，例如 "Apple Distribution"；不填由 Xcode 自动挑选
#   IPA_OUTPUT_DIR        可选，产物根目录（默认 <工程根>/build）
#
# 产物：
#   build/ipa/WingControl-unsigned.ipa   免签名，供 AltStore / Sideloadly / TrollStore 侧载
#   build/ipa/WingControl-signed.ipa    已签名，可直接安装或上传分发

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

PROJECT="WingControl.xcodeproj"
SCHEME="WingControl"
CONFIGURATION="Release"
BUNDLE_ID="com.kela.WingControl"
APP_FILE="WingControl.app"
DISPLAY_NAME="尾翼控制器"

SIGNED=0
for arg in "$@"; do
  case "${arg}" in
    --signed)   SIGNED=1 ;;
    --unsigned) SIGNED=0 ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: ${arg} (可用: --signed / --unsigned / --help)" >&2; exit 2 ;;
  esac
done

BUILD_DIR="${IPA_OUTPUT_DIR:-${ROOT}/build}"
ARCHIVE="${BUILD_DIR}/${SCHEME}.xcarchive"
IPA_DIR="${BUILD_DIR}/ipa"
STAGE="${BUILD_DIR}/stage"
EXPORT_OPTIONS="${STAGE}/ExportOptions.plist"

echo "==> 工程目录：${ROOT}"
echo "==> 导出模式：$([ "${SIGNED}" -eq 1 ] && echo 签名 || echo 免签名)"
xcodebuild -version
xcodebuild -list -project "${PROJECT}" | sed 's/^/    /'

# 每次都做干净构建，避免复用上一次的签名结果
rm -rf "${ARCHIVE}" "${IPA_DIR}" "${STAGE}"
mkdir -p "${IPA_DIR}" "${STAGE}"

COMMON_ARGS=(
  -project "${PROJECT}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "generic/platform=iOS"
  -archivePath "${ARCHIVE}"
)

if [ "${SIGNED}" -eq 1 ]; then
  : "${IOS_TEAM_ID:?签名模式必须设置 IOS_TEAM_ID}"
  : "${IOS_PROFILE_UUID:?签名模式必须设置 IOS_PROFILE_UUID}"
  EXPORT_METHOD="${IOS_EXPORT_METHOD:-ad-hoc}"
  SIGN_ARGS=(
    "DEVELOPMENT_TEAM=${IOS_TEAM_ID}"
    "CODE_SIGN_STYLE=Manual"
    "PROVISIONING_PROFILE_SPECIFIER=${IOS_PROFILE_UUID}"
    "PRODUCT_BUNDLE_IDENTIFIER=${BUNDLE_ID}"
  )
  if [ -n "${IOS_SIGNING_IDENTITY:-}" ]; then
    SIGN_ARGS+=("CODE_SIGN_IDENTITY=${IOS_SIGNING_IDENTITY}")
  fi
else
  # CODE_SIGN_STYLE=Manual 是为了压住工程里 Automatic 签名对 Development Team 的检查
  SIGN_ARGS=(
    "CODE_SIGNING_ALLOWED=NO"
    "CODE_SIGNING_REQUIRED=NO"
    "CODE_SIGN_IDENTITY="
    "CODE_SIGN_STYLE=Manual"
    "DEVELOPMENT_TEAM="
  )
fi

# 不用 `xcodebuild clean`：Xcode 的 clean 会删掉 SYMROOT（默认就是 build/），
# 而归档和导出产物都放在 build/ 下；这里已经 rm -rf 归档目录，本身就是干净的。
echo "==> 开始 archive ..."
# tee 保留完整日志；pipefail 确保 xcodebuild 失败时整个脚本仍以非零退出
xcodebuild "${COMMON_ARGS[@]}" "${SIGN_ARGS[@]}" archive 2>&1 | tee "${BUILD_DIR}/xcodebuild-archive.log"

APP="${ARCHIVE}/Products/Applications/${APP_FILE}"
if [ ! -d "${APP}" ]; then
  echo "归档失败：找不到 ${APP}" >&2
  exit 1
fi

# 顺带校验应用显示名，避免改名后 CI 打出旧名称的包
ACTUAL_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "${APP}/Info.plist")"
if [ "${ACTUAL_NAME}" != "${DISPLAY_NAME}" ]; then
  echo "应用显示名不符: 期望 ${DISPLAY_NAME}, 实际 ${ACTUAL_NAME}" >&2
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Info.plist")"
echo "==> 显示名校验通过: ${ACTUAL_NAME} (${VERSION} / ${BUILD})"
mkdir -p "${IPA_DIR}" "${STAGE}"

if [ "${SIGNED}" -eq 1 ]; then
  cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>teamID</key>
  <string>${IOS_TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key>
    <string>${IOS_PROFILE_UUID}</string>
  </dict>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST
  echo "==> 导出签名 IPA (method=${EXPORT_METHOD}) ..."
  xcodebuild -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportPath "${IPA_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" 2>&1 | tee "${BUILD_DIR}/xcodebuild-export.log"
  EXPORTED="$(find "${IPA_DIR}" -maxdepth 1 -name '*.ipa' -print -quit)"
  if [ -z "${EXPORTED}" ]; then
    echo "exportArchive 未产出 IPA" >&2
    exit 1
  fi
  IPA="${IPA_DIR}/WingControl-signed.ipa"
  if [ "${EXPORTED}" != "${IPA}" ]; then mv "${EXPORTED}" "${IPA}"; fi
else
  # 免签名直接组装 Payload，不要走 -exportArchive（未签名的 archive 会导出失败）。
  # 必须先 mkdir Payload 再 cp -R app Payload/：若目标不存在，
  # cp -R 会把 .app 的内容直接铺进 Payload/，IPA 结构就坏了。
  echo "==> 打包免签名 IPA ..."
  mkdir -p "${STAGE}/Payload"
  cp -R "${APP}" "${STAGE}/Payload/"
  test -f "${STAGE}/Payload/${APP_FILE}/Info.plist" || {
    echo "IPA 结构错误：Payload/${APP_FILE} 不是完整的 .app" >&2
    exit 1
  }
  IPA="${IPA_DIR}/WingControl-unsigned.ipa"
  (cd "${STAGE}" && zip -qry "${IPA}" Payload)
fi

if [ ! -f "${IPA}" ]; then
  echo "IPA 未生成：${IPA}" >&2
  exit 1
fi

echo "==> 产物：${IPA}"
echo "==> 大小：$(du -h "${IPA}" | cut -f1)"
echo "==> SHA256：$(shasum -a 256 "${IPA}" | cut -d' ' -f1)"
unzip -l "${IPA}" | grep -E "Payload/${APP_FILE}/Info\.plist" >/dev/null || {
  echo "IPA 结构异常：缺少 Payload/${APP_FILE}/Info.plist" >&2
  exit 1
}
echo "==> IPA 结构校验通过：Payload/${APP_FILE}/Info.plist"
