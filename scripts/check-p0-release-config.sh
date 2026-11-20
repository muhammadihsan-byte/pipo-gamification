#!/usr/bin/env bash
# Read-only repository validation. No secrets, signing or deployment.
set -euo pipefail
cd "$(dirname "$0")/.."
check() {
  local description="$1" pattern="$2" file="$3"
  if grep -Fq "$pattern" "$file"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s (%s)\n' "$description" "$file" >&2
    exit 1
  fi
}
check "App bundle ID" 'PRODUCT_BUNDLE_IDENTIFIER = com.pipo.app;' Pipo.xcodeproj/project.pbxproj
check "Widget bundle ID" 'PRODUCT_BUNDLE_IDENTIFIER = com.pipo.app.widget;' Pipo.xcodeproj/project.pbxproj
check "App App Group" 'group.com.pipo.app' Pipo/App/Pipo.entitlements
check "Widget App Group" 'group.com.pipo.app' Pipo/Widget/PipoWidget.entitlements
check "OAuth callback scheme" '<string>pipo</string>' Pipo/Info.plist
check "Supabase URL injected through build setting" '$(SUPABASE_URL)' Pipo/Info.plist
check "Supabase anon key injected through build setting" '$(SUPABASE_ANON_KEY)' Pipo/Info.plist
check "StoreKit product identifier" '"productID" : "com.pipo.goalslot"' StoreKit.storekit
check "Legacy ownerless migration gate" 'Legacy ownerless rows' docs/P0_RELEASE_GATE.md
check "Figma badge asset" '"PipoBadge_first-save.png"' Pipo/Assets.xcassets/PipoBadge_first-save.imageset/Contents.json
echo ""
echo "STATIC CHECKS PASSED. This does not authorize release."
echo "NOT VERIFIED: Apple Developer signing, Supabase OAuth/RLS, StoreKit sandbox,"
echo "a physical iPhone, historical SwiftData upgrade or TestFlight."
