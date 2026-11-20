#!/usr/bin/env bash
# Validate both required-reason manifests and their compiled bundle placement.
# This validates source formatting and packaging, not Apple's final privacy
# nutrition label or any third-party SDK's internal manifest/signature.
set -euo pipefail

DERIVED_DATA="${1:-}"
if test -z "$DERIVED_DATA"; then
  echo "Usage: bash scripts/check-privacy-manifest.sh <derived-data-path>" >&2
  exit 1
fi

for source in Pipo/App/PrivacyInfo.xcprivacy Pipo/Widget/PrivacyInfo.xcprivacy; do
  plutil -lint "$source"
  grep -Fq 'NSPrivacyAccessedAPICategoryUserDefaults' "$source"
done
grep -Fq '<string>CA92.1</string>' Pipo/App/PrivacyInfo.xcprivacy
grep -Fq '<string>1C8F.1</string>' Pipo/App/PrivacyInfo.xcprivacy
grep -Fq '<string>1C8F.1</string>' Pipo/Widget/PrivacyInfo.xcprivacy

PRODUCTS="$DERIVED_DATA/Build/Products"
app_manifest="$(find "$PRODUCTS" -path '*/Pipo.app/PrivacyInfo.xcprivacy' -print -quit)"
widget_manifest="$(find "$PRODUCTS" -path '*/PipoWidgetExtension.appex/PrivacyInfo.xcprivacy' -print -quit)"

if test -z "$app_manifest" || test -z "$widget_manifest"; then
  echo "FAIL: privacy manifests must be embedded in both compiled app and widget bundle" >&2
  exit 1
fi

plutil -lint "$app_manifest" "$widget_manifest"
echo "PASS: app and widget privacy manifests embedded with declared UserDefaults reasons"
echo "NOTE: signed release privacy reports, third-party SDK manifests, App Privacy labels and actual App Store upload remain external checks."
