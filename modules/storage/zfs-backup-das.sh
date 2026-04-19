#!/usr/bin/env bash
# zfs-backup-das.sh

# These variables are injected by systemd's Environment directive
# $ZFS_BIN, $SYNCOID_BIN, $PRUNE_BIN, $PRIMARY_POOL, $SECONDARY_POOL, $TARGET_DATASETS

ALL_DATASETS=()
for ds in $TARGET_DATASETS; do
  for sub in $($ZFS_BIN list -H -o name -r "$PRIMARY_POOL/$ds" 2>/dev/null); do
    ALL_DATASETS+=("$sub")
  done
done

for ds_path in "${ALL_DATASETS[@]}"; do
  rel_path="${ds_path#"$PRIMARY_POOL"/}"
  safe_name=$(echo "$ds_path" | tr '/' '_')
  STATE_FILE="$STATE_DIRECTORY/last_synced_$safe_name"

  echo "--- Evaluating $ds_path ---"
  LATEST_SNAP=$($ZFS_BIN list -t snapshot -H -o name -S creation -d 1 "$ds_path" | head -n 1 || true)
  if [ -z "$LATEST_SNAP" ]; then continue; fi

  if [ -f "$STATE_FILE" ]; then
    LAST_SYNCED_SNAP=$(cat "$STATE_FILE")
    if [ "$LATEST_SNAP" == "$LAST_SYNCED_SNAP" ]; then
      echo "Skipping $ds_path: Already fully synced."
      continue
    fi
    
    SNAP_NAME="${LAST_SYNCED_SNAP#*@}"
    WRITTEN=$($ZFS_BIN get -H -p -o value "written@$SNAP_NAME" "$ds_path" 2>/dev/null)
    
    if [ "$WRITTEN" = "0" ]; then
      echo "Skipping $ds_path: 0 bytes written since last sync."
      # We still update the state file to the newer empty snapshot to keep states current
      echo "$LATEST_SNAP" > "$STATE_FILE"
      continue
    elif [ "$WRITTEN" = "-" ]; then
      # If the snapshot no longer exists on the source, 'written' returns '-'.
      # We let this fall through to run syncoid so it can find the next common base.
      echo "Notice: Snapshot $SNAP_NAME no longer exists on source. Proceeding with sync."
    fi
  fi

  echo "Syncing $ds_path to backup pool..."
  if $SYNCOID_BIN --sendoptions=w --no-sync-snap "$ds_path" "$SECONDARY_POOL/$rel_path" -o canmount=noauto; then
    echo "Saving state for $ds_path..."
    echo "$LATEST_SNAP" > "$STATE_FILE"

    if $ZFS_BIN list "$SECONDARY_POOL/$rel_path" >/dev/null 2>&1; then
      echo "Pruning backup snapshots for $rel_path..."
      $PRUNE_BIN -p 'autosnap_' 6M "$SECONDARY_POOL/$rel_path" || true
    fi
  else
    echo "ERROR: Syncoid failed for $ds_path. State file not updated."
  fi
done
