#!/usr/bin/env bash
# zfs-check-sync-das.sh

# These variables are injected by systemd's Environment directive:
# $ZFS_BIN, $PRIMARY_POOL, $TARGET_DATASETS

# 1. Dynamically discover all nested datasets
ALL_DATASETS=()
for ds in $TARGET_DATASETS; do
  # 2>/dev/null suppresses errors if a target dataset hasn't been created yet
  for sub in $($ZFS_BIN list -H -o name -r "$PRIMARY_POOL/$ds" 2>/dev/null); do
    ALL_DATASETS+=("$sub")
  done
done

# 2. Check if ANY dataset in the tree has new data
for ds_path in "${ALL_DATASETS[@]}"; do
  # Create a safe filename for the state file (replace / with _)
  safe_name=$(echo "$ds_path" | tr '/' '_')
  STATE_FILE="$STATE_DIRECTORY/last_synced_$safe_name"

  # Find the most recently created snapshot for this specific dataset
  LATEST_SNAP=$($ZFS_BIN list -t snapshot -H -o name -S creation -d 1 "$ds_path" | head -n 1 || true)
  
  # If there are no snapshots at all, skip to the next dataset
  if [ -z "$LATEST_SNAP" ]; then 
    continue 
  fi

  # If no state file exists, we definitely need to sync
  if [ ! -f "$STATE_FILE" ]; then
    echo "Dataset $ds_path has no state file. Wake sequence initiated."
    exit 0
  fi
  # If the latest snapshot matches what we synced last time, skip
  LAST_SYNCED_SNAP=$(cat "$STATE_FILE")
  if [ "$LATEST_SNAP" == "$LAST_SYNCED_SNAP" ]; then
    continue
  fi

  # Extract just the snapshot name (e.g., autosnap_2023...)
  SNAP_NAME="${LAST_SYNCED_SNAP#*@}"
  # If there is a new snapshot, check if any data was actually written to it
  WRITTEN=$($ZFS_BIN get -H -p -o value "written@$SNAP_NAME" "$ds_path")
  if [ "$WRITTEN" -ne 0 ]; then
    echo "Dataset $ds_path has new data ($WRITTEN bytes written). Wake sequence initiated."
    exit 0 # Exits with success, telling systemd to proceed with ExecStartPre
  fi
done

echo "No datasets need syncing. Keeping drive asleep."
exit 1 # Exits with failure, telling systemd to abort the job cleanly
