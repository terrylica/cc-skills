#!/bin/bash
# Poll AirPods RSSI via system_profiler every ~3s with timestamps.
END=$((SECONDS + ${1:-300}))
while [ $SECONDS -lt $END ]; do
  TS=$(date +%H:%M:%S)
  RSSI=$(system_profiler SPBluetoothDataType 2>/dev/null | /usr/bin/grep -A12 "AirPods Pro:" | /usr/bin/grep -m1 "RSSI:" | /usr/bin/awk '{print $2}')
  echo "[$TS] rssi=${RSSI:-n/a}"
done
