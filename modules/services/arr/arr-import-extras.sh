#!/usr/bin/env bash
# ==============================================================================
# arr-import-extras.sh
# 
# Arr Custom Script (Connect Hook for Radarr & Sonarr)
# Automatically imports extra video & subtitle files (trailers, featurettes,
# bonus content) from the completed download folder into the movie or series
# extra directories upon Download / Upgrade.
#
# Supported Events: Download, Upgrade, Test
# Supported Apps: Radarr, Sonarr
# ==============================================================================

set -euo pipefail

CURRENT_TMP=""
# shellcheck disable=SC2329
cleanup() {
    if [ -n "$CURRENT_TMP" ] && [ -f "$CURRENT_TMP" ]; then
        rm -f "$CURRENT_TMP" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# 1. Identify triggering Arr application and event type
APP_NAME=""
if [ -n "${radarr_eventtype:-}" ]; then
    APP_NAME="Radarr"
    EVENT_TYPE="$radarr_eventtype"
elif [ -n "${sonarr_eventtype:-}" ]; then
    APP_NAME="Sonarr"
    EVENT_TYPE="$sonarr_eventtype"
else
    EVENT_TYPE="${arr_eventtype:-}"
    APP_NAME="Arr"
fi

# 2. Handle Test event from UI
if [ "$EVENT_TYPE" = "Test" ]; then
    echo "[INFO] Test event received from ${APP_NAME}. Script is working!"
    exit 0
fi

# 3. Only proceed on Download, Import, or Upgrade events
case "$EVENT_TYPE" in
    Download|Upgrade|Import|FileImport|FileUpgrade)
        ;;
    *)
        echo "[INFO] Event '${EVENT_TYPE:-unknown}' ignored. Only import and upgrade events are processed."
        exit 0
        ;;
esac

# 4. Resolve paths across Radarr and Sonarr
SERIES_DEST_DIR="${radarr_movie_path:-${sonarr_series_path:-}}"
SOURCE_DIR="${radarr_moviefile_sourcefolder:-${sonarr_episodefile_sourcefolder:-}}"
MAIN_MEDIA_SOURCE="${radarr_moviefile_sourcepath:-${sonarr_episodefile_sourcepath:-}}"
MAIN_MEDIA_DEST="${radarr_moviefile_path:-${sonarr_episodefile_path:-}}"
MEDIA_TITLE="${radarr_movie_title:-${sonarr_series_title:-Unknown}}"

if [ -z "$SERIES_DEST_DIR" ] || [ ! -d "$SERIES_DEST_DIR" ]; then
    echo "[WARN] Destination directory '$SERIES_DEST_DIR' does not exist. Aborting."
    exit 0
fi

if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
    echo "[INFO] Source directory '$SOURCE_DIR' not found or already removed. Nothing to do."
    exit 0
fi

local_src="$(realpath "$SOURCE_DIR" 2>/dev/null || echo "$SOURCE_DIR")"
local_dest="$(realpath "$SERIES_DEST_DIR" 2>/dev/null || echo "$SERIES_DEST_DIR")"

if [[ "$local_src" == "$local_dest" || "$local_src" == "$local_dest"/* ]]; then
    echo "[INFO] Source directory ($SOURCE_DIR) is within destination directory ($SERIES_DEST_DIR). Nothing to import."
    exit 0
fi

local_src_base="$(basename "$local_src" | tr '[:upper:]' '[:lower:]')"
is_shared_root=false
if [[ "$local_src_base" =~ ^(downloads?|completed|torrents?|usenet|incoming|staging|data)$ ]]; then
    is_shared_root=true
fi

if [ "$is_shared_root" = true ] && [ -n "$MAIN_MEDIA_SOURCE" ]; then
    LOCK_KEY="$MAIN_MEDIA_SOURCE"
else
    LOCK_KEY="$local_src"
fi
LOCK_HASH="$(echo -n "$LOCK_KEY" | md5sum | cut -d' ' -f1)"
LOCK_FILE="/tmp/arr-import-${LOCK_HASH}.lock"
exec 200>"$LOCK_FILE"
if ! flock -w 120 200; then
    echo "[WARN] Timed out waiting for import lock on '$LOCK_KEY'. Proceeding with caution."
fi

SEASON_DEST_DIR=""
if [ "$APP_NAME" = "Sonarr" ]; then
    if [ -n "$MAIN_MEDIA_DEST" ]; then
        season_dir="$(dirname "$MAIN_MEDIA_DEST")"
        if [ -d "$season_dir" ] && [[ "$season_dir" == "$SERIES_DEST_DIR"/* ]]; then
            SEASON_DEST_DIR="$season_dir"
        fi
    elif [ -n "${sonarr_episodefile_seasonnumber:-}" ] && [ "${sonarr_episodefile_seasonnumber:-0}" -gt 0 ] 2>/dev/null; then
        padded="$(printf "Season %02d" "$sonarr_episodefile_seasonnumber")"
        unpadded="$(printf "Season %d" "$sonarr_episodefile_seasonnumber")"
        if [ -d "$SERIES_DEST_DIR/$padded" ]; then
            SEASON_DEST_DIR="$SERIES_DEST_DIR/$padded"
        elif [ -d "$SERIES_DEST_DIR/$unpadded" ]; then
            SEASON_DEST_DIR="$SERIES_DEST_DIR/$unpadded"
        fi
    fi
fi

echo "[INFO] [${APP_NAME}] Processing extras for '${MEDIA_TITLE}'"
echo "[INFO] Source: $SOURCE_DIR"
echo "[INFO] Destination: $SERIES_DEST_DIR"
if [ -n "$SEASON_DEST_DIR" ]; then
    echo "[INFO] Season Destination: $SEASON_DEST_DIR"
fi

link_or_copy_file() {
    local src="$1"
    local dest_file="$2"
    local dest_dir
    dest_dir="$(dirname "$dest_file")"

    if [ -n "$MAIN_MEDIA_SOURCE" ] && [ "$(realpath "$src" 2>/dev/null || echo "$src")" = "$(realpath "$MAIN_MEDIA_SOURCE" 2>/dev/null || echo "$MAIN_MEDIA_SOURCE")" ]; then
        return 0
    fi
    if [ -n "$MAIN_MEDIA_DEST" ] && [ "$(basename "$src")" = "$(basename "$MAIN_MEDIA_DEST")" ]; then
        return 0
    fi
    if [ -n "$MAIN_MEDIA_DEST" ] && [ -e "$MAIN_MEDIA_DEST" ]; then
        if [ "$src" -ef "$MAIN_MEDIA_DEST" ]; then
            return 0
        fi
        local src_sz dest_sz
        src_sz="$(stat -c%s "$src" 2>/dev/null || echo 0)"
        dest_sz="$(stat -c%s "$MAIN_MEDIA_DEST" 2>/dev/null || echo 1)"
        if [ "$dest_sz" -gt 0 ] && [ "$src_sz" -eq "$dest_sz" ]; then
            echo "[DEBUG] Skipping file matching main media size: $src"
            return 0
        fi
    fi

    local lower_name
    lower_name="$(basename "$src" | tr '[:upper:]' '[:lower:]')"
    local sample_regex='(^|[-_. ])sample([-_. ]|\.[^.]+$)'
    if [[ "$lower_name" =~ $sample_regex || "$lower_name" == "sample.mkv" || "$lower_name" == "sample.mp4" ]]; then
        echo "[DEBUG] Skipping sample file: $src"
        return 0
    fi

    mkdir -p "$dest_dir"
    chmod 2775 "$dest_dir" 2>/dev/null || true

    if [ -e "$dest_file" ] && [ "$src" -ef "$dest_file" ]; then
        return 0
    fi

    if [ -f "$dest_file" ]; then
        local target_sz existing_dest_sz
        target_sz="$(stat -c%s "$src" 2>/dev/null || echo 1)"
        existing_dest_sz="$(stat -c%s "$dest_file" 2>/dev/null || echo 2)"
        if [ "$target_sz" -eq "$existing_dest_sz" ]; then
            echo "[DEBUG] Target file '$dest_file' already exists with identical size. Skipping."
            return 0
        fi
    fi

    echo "[INFO] Importing extra: $src -> $dest_file"
    if cp -lf "$src" "$dest_file" 2>/dev/null; then
        chmod 664 "$dest_file" 2>/dev/null || true
        return 0
    fi

    local tmp_dest="${dest_file}.tmp.$$"
    CURRENT_TMP="$tmp_dest"
    if cp -p "$src" "$tmp_dest"; then
        chmod 664 "$tmp_dest" 2>/dev/null || true
        mv -f "$tmp_dest" "$dest_file"
        CURRENT_TMP=""
    else
        rm -f "$tmp_dest" 2>/dev/null || true
        CURRENT_TMP=""
        return 1
    fi
}

resolve_category() {
    local folder_str="$1"
    case "$folder_str" in
        *extras*|*bonus*|*featurette*|*"special feature"*|*"making of"*|*"gag reel"*|season*extra*)
            echo "Featurettes"
            ;;
        *"behind the scene"*|bts)
            echo "Behind The Scenes"
            ;;
        *"deleted scene"*)
            echo "Deleted Scenes"
            ;;
        *trailer*|*teaser*)
            echo "Trailers"
            ;;
        *interview*)
            echo "Interviews"
            ;;
        *short*)
            echo "Shorts"
            ;;
        *)
            echo ""
            ;;
    esac
}

import_extra_folder() {
    local source_sub="$1"
    local category_name="$2"
    local default_base_dir="$3"

    while IFS= read -r -d '' vid; do
        local rel_path="${vid#"$source_sub"/}"
        local target_file=""

        # If file is nested inside a Season XX directory within extras, route directly to that season
        if [ "$APP_NAME" = "Sonarr" ] && [[ "$rel_path" =~ ^([Ss]eason[[:space:]_-]*0*([0-9]+)|[Ss]0*([0-9]+))/(.*)$ ]]; then
            local season_num="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
            local inner_rel="${BASH_REMATCH[4]}"
            local padded_s
            padded_s="$(printf "Season %02d" "$season_num")"
            local unpadded_s
            unpadded_s="$(printf "Season %d" "$season_num")"

            local season_dest="$SERIES_DEST_DIR/$padded_s"
            if [ -d "$SERIES_DEST_DIR/$padded_s" ]; then
                season_dest="$SERIES_DEST_DIR/$padded_s"
            elif [ -d "$SERIES_DEST_DIR/$unpadded_s" ]; then
                season_dest="$SERIES_DEST_DIR/$unpadded_s"
            fi
            target_file="$season_dest/$category_name/$inner_rel"
        else
            target_file="$default_base_dir/$category_name/$rel_path"
        fi

        link_or_copy_file "$vid" "$target_file" || echo "[WARN] Failed to import extra: $vid"
    done < <(fd -0 -I -t f \
        -e mkv -e mp4 -e avi -e ts -e m4v -e mov \
        -e srt -e vtt -e sub -e idx -e sup -e ass \
        . "$source_sub")
}

# Process subfolders
shopt -s nullglob

if [ "$is_shared_root" = false ]; then
    for sub in "$SOURCE_DIR"/*/; do
        [ -d "$sub" ] || continue
        sub="${sub%/}"
        folder_name="$(basename "$sub")"
        lower_folder="$(echo "$folder_name" | tr '[:upper:]' '[:lower:]' | tr '_.-' ' ')"

        category="$(resolve_category "$lower_folder")"

        if [ -n "$category" ]; then
            target_base="$SERIES_DEST_DIR"
            if [ "$APP_NAME" = "Sonarr" ]; then
                if [[ "$lower_folder" =~ (^|[[:space:]])season[[:space:]]*0*([0-9]+) || "$lower_folder" =~ (^|[[:space:]])s0*([0-9]+)[[:space:]]*extra ]]; then
                    folder_season="${BASH_REMATCH[2]}"
                    padded_s="$(printf "Season %02d" "$folder_season")"
                    unpadded_s="$(printf "Season %d" "$folder_season")"
                    if [ -d "$SERIES_DEST_DIR/$padded_s" ]; then
                        target_base="$SERIES_DEST_DIR/$padded_s"
                    elif [ -d "$SERIES_DEST_DIR/$unpadded_s" ]; then
                        target_base="$SERIES_DEST_DIR/$unpadded_s"
                    fi
                elif [ -n "$SEASON_DEST_DIR" ] && [[ "$lower_folder" =~ season.*extra ]]; then
                    target_base="$SEASON_DEST_DIR"
                fi
            fi

            import_extra_folder "$sub" "$category" "$target_base"

        elif [ "$APP_NAME" = "Sonarr" ] && [[ "$lower_folder" =~ ^([Ss]eason[[:space:]_-]*0*([0-9]+)|[Ss]0*([0-9]+))$ ]]; then
            season_num="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
            padded_s="$(printf "Season %02d" "$season_num")"
            unpadded_s="$(printf "Season %d" "$season_num")"
            season_dest="$SERIES_DEST_DIR/$padded_s"
            if [ -d "$SERIES_DEST_DIR/$padded_s" ]; then
                season_dest="$SERIES_DEST_DIR/$padded_s"
            elif [ -d "$SERIES_DEST_DIR/$unpadded_s" ]; then
                season_dest="$SERIES_DEST_DIR/$unpadded_s"
            fi

            for season_sub in "$sub"/*/; do
                [ -d "$season_sub" ] || continue
                season_sub="${season_sub%/}"
                inner_folder_name="$(basename "$season_sub")"
                inner_lower="$(echo "$inner_folder_name" | tr '[:upper:]' '[:lower:]' | tr '_.-' ' ')"
                inner_category="$(resolve_category "$inner_lower")"
                if [ -n "$inner_category" ]; then
                    import_extra_folder "$season_sub" "$inner_category" "$season_dest"
                fi
            done
        fi
    done
fi

shopt -u nullglob

# Process loose files in root
shopt -s nullglob
while IFS= read -r -d '' vid; do
    fname="$(basename "$vid")"
    lower_fname="$(echo "$fname" | tr '[:upper:]' '[:lower:]')"

    # Skip TV episodes if present as loose files
    if [[ "$lower_fname" =~ (^|[-_. ])(s[0-9]{1,2}e[0-9]{1,2}|[0-9]{1,2}x[0-9]{1,2})([-_. ]|$) ]]; then
        continue
    fi

    # Strictly limit loose root files to matching "featurettes"
    if [[ "$lower_fname" =~ (^|[-_. ])(featurette|featurettes)([-_. ]|$) ]]; then
        target_sub="$SERIES_DEST_DIR/Featurettes"
    else
        continue
    fi

    target_file="$target_sub/$fname"
    link_or_copy_file "$vid" "$target_file" || echo "[WARN] Failed to import loose extra: $vid"

    vid_base="${vid%.*}"
    for sub_candidate in "${vid_base}"*.srt "${vid_base}"*.vtt "${vid_base}"*.sub "${vid_base}"*.idx "${vid_base}"*.sup "${vid_base}"*.ass; do
        if [ -f "$sub_candidate" ]; then
            cand_name="$(basename "$sub_candidate")"
            link_or_copy_file "$sub_candidate" "$target_sub/$cand_name" || echo "[WARN] Failed to import subtitle: $sub_candidate"
        fi
    done
done < <(fd -0 -I -t f --max-depth 1 -e mkv -e mp4 -e avi -e ts -e m4v -e mov . "$SOURCE_DIR")
shopt -u nullglob

echo "[INFO] [${APP_NAME}] Finished extras processing for '${MEDIA_TITLE}'."
exit 0
