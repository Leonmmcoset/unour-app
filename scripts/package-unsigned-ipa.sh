#!/usr/bin/env bash
set -euo pipefail
project_root="${GITHUB_WORKSPACE:-$(pwd)}"
app_path="$project_root/build/ios/iphoneos/Runner.app"
ipa_path="$project_root/build/ios/ipa/Unour-unsigned.ipa"
if [[ ! -d "$app_path" ]]; then
  echo "Missing $app_path. Run flutter build ios --release --no-codesign first." >&2
  exit 1
fi
staging_path="$(mktemp -d)"
trap 'rm -rf "$staging_path"' EXIT
mkdir -p "$staging_path/Payload" "$(dirname "$ipa_path")"
# ditto preserves framework symlinks and the application bundle structure.
ditto "$app_path" "$staging_path/Payload/Runner.app"
rm -f "$ipa_path"
(cd "$staging_path" && /usr/bin/zip --symlinks --quiet --recurse-paths "$ipa_path" Payload)
/usr/bin/unzip -tq "$ipa_path"
echo "Unsigned IPA: $ipa_path"
