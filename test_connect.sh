#!/bin/bash
TOKEN=$(curl -s -X POST http://89.208.107.67:8500/auth/device \
  -H 'Content-Type: application/json' \
  -d '{"device_id":"test-device-warp-001"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

echo "=== TOKEN obtained ==="
echo "=== POST /vpn/connect/3 ==="
curl -s -X POST http://89.208.107.67:8500/vpn/connect/3 \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  | python3 -m json.tool
