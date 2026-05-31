#!/bin/bash

set -e

VERSION="$1"
BASE_URL="http://update.rwfc.net:8000/RetroRewind/zip"

ROOT_DIR=$(pwd)
WORK_DIR="$ROOT_DIR/workdir"
LANG_EXPORT_DIR="$WORK_DIR/lang_export"

if [ -z "$VERSION" ]; then
    echo "Error: No version provided."
    exit 1
fi

if ! command -v wszst >/dev/null || ! command -v wbmgt >/dev/null; then
    echo "Error: wszst or wbmgt not found in PATH"
    exit 1
fi

echo "🚀 Starting build for version: $VERSION"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$LANG_EXPORT_DIR"

apply_patches() {
    local target_base="$1/Language"

    if [ ! -d "$target_base" ]; then
        echo "   ⚠️ No Language folder found. Skipping patches."
        return 0
    fi

    while IFS= read -r -d '' szs_file; do
        modified=false

        rm -rf "$WORK_DIR/temp_szs"

        wszst extract \
            "$szs_file" \
            --dest "$WORK_DIR/temp_szs" \
            --quiet \
            --overwrite

        while IFS= read -r -d '' bmg_file; do

            wbmgt decode \
                "$bmg_file" \
                --dest "$WORK_DIR/temp_msg.txt" \
                --quiet \
                --overwrite

            cp \
                "$WORK_DIR/temp_msg.txt" \
                "$WORK_DIR/temp_msg_before.txt"

            perl -pi -e 's/(?<!Baby )Daisy \(Schwarz\/Türkis\)/\\c{yor3}Steve/g' "$WORK_DIR/temp_msg.txt"
            perl -pi -e 's/(?<!Baby )Daisy \(Black\/Teal\)/\\c{yor3}Steve/g' "$WORK_DIR/temp_msg.txt"
            perl -pi -e 's/\bTheBeefBai\b/heyFordy/g' "$WORK_DIR/temp_msg.txt"
            perl -pi -e 's/Mach-Bike/\\c{yor4}KFC\\c{off}-\\c{yor2}Mofa/g' "$WORK_DIR/temp_msg.txt"

            if ! cmp -s \
                "$WORK_DIR/temp_msg_before.txt" \
                "$WORK_DIR/temp_msg.txt"; then
                modified=true
            fi

            rm -f "$WORK_DIR/temp_msg_before.txt"

            wbmgt encode \
                "$WORK_DIR/temp_msg.txt" \
                --dest "$bmg_file" \
                --quiet \
                --overwrite

            rm -f "$WORK_DIR/temp_msg.txt"

        done < <(find "$WORK_DIR/temp_szs" -type f -name "*.bmg" -print0)

        wszst create \
            "$WORK_DIR/temp_szs" \
            --dest "$szs_file" \
            --overwrite \
            --quiet

        if [ "$modified" = true ]; then
            rel_path="${szs_file#*/Language/}"

            mkdir -p "$LANG_EXPORT_DIR/$(dirname "$rel_path")"

            cp \
                "$szs_file" \
                "$LANG_EXPORT_DIR/$rel_path"

            echo "      ➜ Exported: $rel_path"
        fi

        rm -rf "$WORK_DIR/temp_szs"

    done < <(find "$target_base" -type f -name "*.szs" -print0)
}

echo "📦 Processing MASTER Release (RetroRewind.zip)..."

wget -q \
    "$BASE_URL/RetroRewind.zip" \
    -O "$WORK_DIR/RetroRewind.zip"

unzip -q \
    "$WORK_DIR/RetroRewind.zip" \
    -d "$WORK_DIR/master"

mkdir -p "$WORK_DIR/master/RetroRewind6"
echo "$VERSION" > "$WORK_DIR/master/RetroRewind6/version.txt"

echo "   Applying text patches to all languages..."
apply_patches "$WORK_DIR/master/RetroRewind6"

cd "$WORK_DIR/master"
zip -r -q "$ROOT_DIR/Fordy-RR-${VERSION}.zip" .
cd "$ROOT_DIR"

echo "✅ Created Fordy-RR-${VERSION}.zip"

MAJOR_MINOR=$(echo "$VERSION" | cut -d. -f1-2)
MAX_PATCH=$(echo "$VERSION" | cut -d. -f3)

echo "🔄 Starting Update Loop for ${MAJOR_MINOR}.x..."

for ((i=0; i<=MAX_PATCH; i++)); do

    CURRENT_VER="${MAJOR_MINOR}.${i}"

    echo "------------------------------------------------"
    echo "Processing Update Version: $CURRENT_VER"

    TARGET_ZIP_NAME="UPDATE-Fordy-RR-${CURRENT_VER}.zip"
    DL_SUCCESS=false

    if wget -q \
        "$BASE_URL/${CURRENT_VER}.zip" \
        -O "$WORK_DIR/update_src.zip"; then

        DL_SUCCESS=true

    elif [ "$i" -eq 0 ] && wget -q \
        "$BASE_URL/${MAJOR_MINOR}.zip" \
        -O "$WORK_DIR/update_src.zip"; then

        echo "   Found via fallback: ${MAJOR_MINOR}.zip"
        DL_SUCCESS=true
    fi

    if [ "$DL_SUCCESS" = false ]; then
        echo "   ❌ Source zip not found on server. Skipping."
        continue
    fi

    rm -rf "$WORK_DIR/temp_update"
    mkdir -p "$WORK_DIR/temp_update"

    unzip -q \
        "$WORK_DIR/update_src.zip" \
        -d "$WORK_DIR/temp_update"

    mkdir -p "$WORK_DIR/temp_update/RetroRewind6"
    echo "$CURRENT_VER" > \
        "$WORK_DIR/temp_update/RetroRewind6/version.txt"

    echo "   Attempting to patch files..."
    apply_patches "$WORK_DIR/temp_update/RetroRewind6"

    cd "$WORK_DIR/temp_update"
    zip -r -q "$ROOT_DIR/$TARGET_ZIP_NAME" .
    cd "$ROOT_DIR"

    echo "✅ Created $TARGET_ZIP_NAME"

    rm -f "$WORK_DIR/update_src.zip"
done

if find "$LANG_EXPORT_DIR" -type f | grep -q .; then
    cd "$LANG_EXPORT_DIR"
    zip -r -q "$ROOT_DIR/lang.zip" .
    cd "$ROOT_DIR"

    echo "✅ Created lang.zip"
else
    echo "ℹ️ No modified language files found."
fi

echo "🎉 All builds complete."