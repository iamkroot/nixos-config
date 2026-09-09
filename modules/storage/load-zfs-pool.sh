#!/usr/bin/env bash
set -euo pipefail

POOL="$1"

zfs get -H -o name,value keylocation -r "$POOL" | \
while IFS=$'\t' read -r name value || [ -n "$name" ]; do
  if [[ "$value" == file://* ]]; then
    keystatus=$(zfs get -H -o value keystatus "$name")

    if [ "$keystatus" = "unavailable" ]; then
      echo "Loading key for $name from $value..."
      zfs load-key "$name" || true
    else
      echo "Key for $name is already loaded. Skipping..."
    fi
  fi
done

# Mount the datasets natively
zfs mount -a || true
