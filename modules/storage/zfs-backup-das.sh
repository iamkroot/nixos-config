#!/usr/bin/env bash
# zfs-backup-das.sh

# These variables are injected by systemd's Environment directive
# $ZFS_BIN, $SYNCOID_BIN, $PRUNE_BIN, $PRIMARY_POOL, $SECONDARY_POOL, $TARGET_DATASETS
# $NTFY_URL, $NTFY_TOKEN_FILE

ntfy_notify() {
  local title="$1" message="$2" priority="${3:-default}" tags="${4:-floppy_disk}"
  if [ -n "$NTFY_URL" ] && [ -f "$NTFY_TOKEN_FILE" ]; then
    curl -s -o /dev/null \
      -H "Authorization: Bearer $(cat "$NTFY_TOKEN_FILE")" \
      -H "Title: $title" \
      -H "Priority: $priority" \
      -H "Tags: $tags" \
      -d "$message" \
      "$NTFY_URL" || true
  fi
}

ALL_DATASETS=()
for ds in $TARGET_DATASETS; do
  for sub in $($ZFS_BIN list -H -o name -r "$PRIMARY_POOL/$ds" 2>/dev/null); do
    ALL_DATASETS+=("$sub")
  done
done

FAILED_DATASETS=0

for ds_path in "${ALL_DATASETS[@]}"; do
  rel_path="${ds_path#"$PRIMARY_POOL"/}"
  safe_name=$(echo "$ds_path" | tr '/' '_')
  STATE_FILE="$STATE_DIRECTORY/last_synced_$safe_name"
  target_ds="$SECONDARY_POOL/$rel_path"

  echo "--- Evaluating $ds_path ---"
  LATEST_SNAP=$($ZFS_BIN list -t snapshot -H -o name -S creation -d 1 "$ds_path" | head -n 1 || true)
  if [ -z "$LATEST_SNAP" ]; then continue; fi

  # Ensure parent dataset exists on secondary pool before receiving
  parent_ds="${target_ds%/*}"
  if [ "$parent_ds" != "$target_ds" ] && ! $ZFS_BIN list "$parent_ds" >/dev/null 2>&1; then
    echo "Creating missing parent dataset $parent_ds..."
    $ZFS_BIN create -p "$parent_ds" || true
  fi

  # Only trust state file if the target dataset actually exists on the secondary pool
  if [ -f "$STATE_FILE" ] && $ZFS_BIN list "$target_ds" >/dev/null 2>&1; then
    LAST_SYNCED_SNAP=$(cat "$STATE_FILE")
    if [ "$LATEST_SNAP" == "$LAST_SYNCED_SNAP" ]; then
      echo "Skipping $ds_path: Already fully synced."
      continue
    fi

    SNAP_NAME="${LAST_SYNCED_SNAP#*@}"
    WRITTEN=$($ZFS_BIN get -H -p -o value "written@$SNAP_NAME" "$ds_path" 2>/dev/null)

    if [ "$WRITTEN" = "0" ]; then
      echo "Skipping $ds_path: 0 bytes written since last sync."
      echo "$LATEST_SNAP" > "$STATE_FILE"
      continue
    elif [ "$WRITTEN" = "-" ]; then
      # If the snapshot no longer exists on the source, 'written' returns '-'.
      # We let this fall through to run syncoid so it can find the next common base.
      echo "Notice: Snapshot $SNAP_NAME no longer exists on source. Proceeding with sync."
    fi
  fi

  echo "Syncing $ds_path to backup pool..."
  if $SYNCOID_BIN --sendoptions=w --no-sync-snap "$ds_path" "$target_ds" -o canmount=noauto; then
    echo "Saving state for $ds_path..."
    echo "$LATEST_SNAP" > "$STATE_FILE"

    if $ZFS_BIN list "$target_ds" >/dev/null 2>&1; then
      echo "Pruning backup snapshots for $rel_path..."
      $PRUNE_BIN -p 'autosnap_' 6M "$target_ds" || true
    fi
  else
    # Check if the failure is due to snapshot divergence (target exists but no common snapshot)
    if $ZFS_BIN list "$target_ds" >/dev/null 2>&1; then
      echo "WARN: Syncoid failed for $ds_path. Target exists — checking for snapshot divergence..."

      # Check if there are ANY common snapshots between source and target
      src_snaps=$($ZFS_BIN list -t snapshot -H -o name -d 1 "$ds_path" 2>/dev/null |
        while IFS= read -r s; do echo "${s#*@}"; done)
      tgt_snaps=$($ZFS_BIN list -t snapshot -H -o name -d 1 "$target_ds" 2>/dev/null |
        while IFS= read -r s; do echo "${s#*@}"; done)
      common=$(comm -12 <(echo "$src_snaps" | sort) <(echo "$tgt_snaps" | sort))

      if [ -z "$common" ]; then
        # No common snapshots — diverged. Rename and retry fresh.
        diverged_name="${target_ds}_diverged_$(date +%s)"
        echo "WARN: No common snapshots between $ds_path and $target_ds."
        echo "WARN: Renaming diverged target to $diverged_name and retrying fresh sync..."
        if $ZFS_BIN rename "$target_ds" "$diverged_name"; then
          ntfy_notify "ZFS Backup: Snapshot Divergence" \
            "Auto-resolved divergence on $target_ds. Old data renamed to $diverged_name. Fresh sync in progress." \
            "default" "warning,recycle"
          # Retry syncoid — this time it'll do a fresh initial send
          if $SYNCOID_BIN --sendoptions=w --no-sync-snap "$ds_path" "$target_ds" -o canmount=noauto; then
            echo "Saving state for $ds_path after fresh sync..."
            echo "$LATEST_SNAP" > "$STATE_FILE"

            if $ZFS_BIN list "$target_ds" >/dev/null 2>&1; then
              echo "Pruning backup snapshots for $rel_path..."
              $PRUNE_BIN -p 'autosnap_' 6M "$target_ds" || true
            fi
          else
            echo "ERROR: Fresh sync also failed for $ds_path. State file not updated."
            FAILED_DATASETS=$((FAILED_DATASETS + 1))
          fi
        else
          echo "ERROR: Could not rename diverged dataset $target_ds. State file not updated."
          FAILED_DATASETS=$((FAILED_DATASETS + 1))
        fi
      else
        # Target exists, has common snapshots, but syncoid still failed — some other error
        echo "ERROR: Syncoid failed for $ds_path (has common snapshots — not a divergence issue). State file not updated."
        FAILED_DATASETS=$((FAILED_DATASETS + 1))
      fi
    else
      # Target doesn't exist — syncoid should have created it. Something else went wrong.
      echo "ERROR: Syncoid failed for $ds_path (target does not exist). State file not updated."
      FAILED_DATASETS=$((FAILED_DATASETS + 1))
    fi
  fi
done

if [ "$FAILED_DATASETS" -gt 0 ]; then
  echo "CRITICAL: $FAILED_DATASETS dataset(s) failed replication to secondary pool."
  ntfy_notify "ZFS Backup Failed" \
    "$FAILED_DATASETS dataset(s) failed replication from $PRIMARY_POOL to $SECONDARY_POOL. Check journalctl -u zfs-backup-das." \
    "high" "rotating_light"
  exit 1
fi

echo "All datasets replicated successfully."
