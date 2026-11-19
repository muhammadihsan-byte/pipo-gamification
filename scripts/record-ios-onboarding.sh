#!/usr/bin/env bash
# One controlled Simulator run records authenticated personalization and optional widget with V4 motion.
# Builds the UI test target only once; no sign-in, payment, or TestFlight steps.
set -euo pipefail

: "${SIMULATOR_UDID:?A Simulator device is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

mkdir -p validation/videos validation/ui-test-logs
derived="$RUNNER_TEMP/PipoOnboardingDerivedData"
output="validation/videos/Pipo-Post-Login-Onboarding.mp4"
recording_pid=""

stop_recording() {
  if test -n "$recording_pid"; then
    kill -INT "$recording_pid" 2>/dev/null || true
    wait "$recording_pid" 2>/dev/null || true
    recording_pid=""
  fi
}
trap stop_recording EXIT

echo "Building onboarding UI test target once..."
xcodebuild \
  -project Pipo.xcodeproj \
  -scheme Pipo \
  -configuration Debug \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$derived" \
  -parallel-testing-enabled NO \
  -only-testing:PipoUITests/PipoUIRecordingTests/testPostLoginPersonalizationAndWidgetPreview \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build-for-testing 2>&1 | tee validation/ui-test-logs/onboarding-build.log

xctestrun="$(find "$derived/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)"
if test -z "$xctestrun"; then
  echo "Missing built XCUITest bundle" >&2
  exit 1
fi

xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl status_bar "$SIMULATOR_UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true

echo "Recording post-login onboarding and returning-account skip in one Simulator session..."
xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 --force "$output" \
  >validation/ui-test-logs/onboarding-recorder.log 2>&1 &
recording_pid=$!
sleep 2
if ! kill -0 "$recording_pid" 2>/dev/null; then
  echo "Simulator screen recording could not start" >&2
  exit 1
fi

set +e
xcodebuild \
  -xctestrun "$xctestrun" \
  -destination "id=$SIMULATOR_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:PipoUITests/PipoUIRecordingTests/testPostLoginPersonalizationAndWidgetPreview \
  -resultBundlePath "$RUNNER_TEMP/PipoTestResults.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test-without-building 2>&1 | tee validation/ui-test-logs/onboarding-test.log
status=${PIPESTATUS[0]}
set -e
stop_recording

if test "$status" -ne 0; then
  echo "Onboarding XCUITest failed. Review validation logs." >&2
  exit "$status"
fi

python3 - "$output" <<'PY'
import os
import sys

path = sys.argv[1]
with open(path, "rb") as file:
    head = file.read(64)
    file.seek(max(0, os.path.getsize(path) - 1024 * 1024))
    tail = file.read()
assert os.path.getsize(path) > 50000, "Recording is unexpectedly small"
assert b"ftyp" in head, "MP4 header is missing"
assert b"moov" in tail, "MP4 was not finalized"
print(f"Validated onboarding MP4: {os.path.getsize(path)} bytes")
PY

shasum -a 256 "$output" >validation/videos/SHA256SUMS
echo "Post-login personalization and widget onboarding test passed. One MP4 is available."
