#!/usr/bin/env bash
# Two real XCUITest journeys, one video per flow. Build once, run twice.
set -euo pipefail

if test -z "$SIMULATOR_UDID" || test -z "$RUNNER_TEMP"; then
  echo "SIMULATOR_UDID and RUNNER_TEMP are required." >&2
  exit 1
fi
mkdir -p validation/videos validation/ui-test-logs
derived="$RUNNER_TEMP/PipoVisualQADerivedData"
recording_pid=""
failures=0

stop_recording() {
  if test -n "$recording_pid"; then
    # SIGINT finalizes MP4; SIGTERM can truncate the video.
    kill -INT "$recording_pid" 2>/dev/null || true
    wait "$recording_pid" 2>/dev/null || true
    recording_pid=""
  fi
}
trap stop_recording EXIT

echo "Building native PipoUITests once..."
xcodebuild \
  -project Pipo.xcodeproj \
  -scheme Pipo \
  -configuration Debug \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$derived" \
  -parallel-testing-enabled NO \
  -only-testing:PipoUITests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build-for-testing 2>&1 | tee validation/ui-test-logs/build-for-testing.log

xctestrun="$(find "$derived/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)"
if test -z "$xctestrun"; then
  echo "Xcode did not generate an .xctestrun file." >&2
  exit 1
fi

xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl status_bar "$SIMULATOR_UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true

run_journey() {
  flow="$1"
  test_method="$2"
  output="validation/videos/Pipo-$flow-Saving.mp4"
  echo "Recording native $flow journey..."
  xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 --force "$output" \
    >"validation/ui-test-logs/$flow-recorder.log" 2>&1 &
  recording_pid=$!
  sleep 2
  if ! kill -0 "$recording_pid" 2>/dev/null; then
    echo "Screen recorder failed for $flow" >&2
    failures=$((failures + 1))
    stop_recording
    return
  fi

  set +e
  xcodebuild \
    -xctestrun "$xctestrun" \
    -destination "id=$SIMULATOR_UDID" \
    -parallel-testing-enabled NO \
    -only-testing:"PipoUITests/PipoUIRecordingTests/$test_method" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    test-without-building 2>&1 | tee "validation/ui-test-logs/$flow-test.log"
  test_status=$?
  set -e
  stop_recording

  if test "$test_status" -ne 0; then
    echo "$flow UI navigation failed (exit $test_status)" >&2
    failures=$((failures + 1))
  fi
  if ! test -s "$output"; then
    echo "$flow MP4 is missing or empty." >&2
    failures=$((failures + 1))
    return
  fi

  # Require finalized H264 MP4 metadata, not just a nonempty file.
  if ! python3 - "$output" <<'PY'
import os
import sys
filename = sys.argv[1]
with open(filename, "rb") as file:
    header = file.read(64)
    file.seek(max(0, os.path.getsize(filename) - 1024 * 1024))
    tail = file.read()
assert os.path.getsize(filename) > 50000, "MP4 unexpectedly short"
assert b"ftyp" in header, "MP4 header missing"
assert b"moov" in tail, "MP4 finalization metadata missing"
print(f"Validated {filename}: {os.path.getsize(filename)} bytes")
PY
  then
    failures=$((failures + 1))
  fi
  xcrun simctl terminate "$SIMULATOR_UDID" com.pipo.app 2>/dev/null || true
  sleep 2
}

run_journey "Personal" "testPersonalSavingJourney"
run_journey "Group" "testGroupSavingJourney"

shasum -a 256 validation/videos/*.mp4 >validation/videos/SHA256SUMS 2>/dev/null || true
if test "$failures" -ne 0; then
  echo "Visual QA encountered $failures failure(s). Review both MP4s and logs." >&2
  exit 1
fi
echo "Both Pipo Saving journeys passed; two finalized MP4s are available."
