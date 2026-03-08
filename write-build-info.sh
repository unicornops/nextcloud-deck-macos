#!/bin/bash
set -euo pipefail

build_info_path="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/BuildInfo.plist"

resolve_commit() {
  if [[ -n "${GIT_COMMIT_HASH:-}" && "${GIT_COMMIT_HASH}" != "unknown" ]]; then
    printf '%s' "${GIT_COMMIT_HASH}"
    return
  fi

  git -C "${SRCROOT}" rev-parse HEAD 2>/dev/null || printf 'unknown'
}

resolve_ref() {
  if [[ -n "${BUILD_REF:-}" && "${BUILD_REF}" != "local" ]]; then
    printf '%s' "${BUILD_REF}"
    return
  fi

  git -C "${SRCROOT}" describe --tags --always --dirty 2>/dev/null || printf 'local'
}

resolve_build_date() {
  if [[ -n "${BUILD_DATE_UTC:-}" && "${BUILD_DATE_UTC}" != "unknown" && "${BUILD_DATE_UTC}" != "local" ]]; then
    printf '%s' "${BUILD_DATE_UTC}"
    return
  fi

  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

mkdir -p "$(dirname "${build_info_path}")"

cat > "${build_info_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>BuildVersion</key>
  <string>${MARKETING_VERSION:-Unknown}</string>
  <key>BuildNumber</key>
  <string>${CURRENT_PROJECT_VERSION:-Unknown}</string>
  <key>BuildRef</key>
  <string>$(resolve_ref)</string>
  <key>BuildGitCommit</key>
  <string>$(resolve_commit)</string>
  <key>BuildDateUTC</key>
  <string>$(resolve_build_date)</string>
</dict>
</plist>
EOF
