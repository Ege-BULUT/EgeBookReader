#!/bin/sh
# Runs the end-to-end suite (integration_test/) on a running emulator or phone, offline.
# Usage: tool/e2e.sh <device>   a device id (flutter devices, e.g. emulator-5554) or a running emulator's AVD name.
# It installs a debug build over the app. The test runs in folders of its own, so the device's library stays as it is.
# Exits non-zero when a test fails.
set -eu
if [ $# -ne 1 ]; then
  echo "usage: $0 <device id or AVD name>" >&2
  exit 2
fi
device=$1
# An AVD name (unlucky_root) becomes the serial of the emulator running it.
for serial in $(adb devices | awk '/^emulator-/ {print $1}'); do
  if [ "$(adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r')" = "$1" ]; then device=$serial; fi
done
cd "$(dirname "$0")/.."
exec flutter test integration_test -d "$device"
