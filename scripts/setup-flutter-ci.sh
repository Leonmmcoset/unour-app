#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?This script runs in GitHub Actions}"
: "${GITHUB_PATH:?GitHub Actions path file is required}"
: "${FLUTTER_VERSION:?Pin the Flutter version in the workflow}"
sdk_path="$RUNNER_TEMP/unour-flutter"
git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$sdk_path"
echo "$sdk_path/bin" >> "$GITHUB_PATH"
"$sdk_path/bin/flutter" --no-version-check config --no-analytics
"$sdk_path/bin/flutter" --no-version-check --version
