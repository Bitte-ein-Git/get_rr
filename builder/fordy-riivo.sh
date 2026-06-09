#!/bin/bash

set -e

VERSION="$1"
BASE_URL="http://update.rwfc.net:8000/RetroRewind/zip"

ROOT_DIR=$(pwd)
WORK_DIR="$ROOT_DIR/workdir"

# Input validation
if [ -z "$VERSION" ]; then
  echo "Error: No version provided."
  exit 1
fi

# Dependency check
if ! command -v wszst &> /dev/null || ! command -v wbmgt &> /dev/null; then
    echo "Error: wszst or wbmgt not found in PATH"
    exit 1
fi

echo "🚀 Starting build for version: $VERSION"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Patch function
apply_patches() {
    local target_base="$1"
    local lang_dir="$target_base/Language"
    local bin_dir="$target_base/Binaries"
    
    if [ ! -d "$lang_dir" ]; then
        echo "   ⚠️ No Language folder found. Skipping patches."
        return 0
    fi

    find "$lang_dir" -name "*.szs" | while read -r szs_file; do
        wszst extract "$szs_file" --dest "$WORK_DIR/temp_szs" --quiet --overwrite
        
        find "$WORK_DIR/temp_szs" -name "*.bmg" | while read -r bmg_file; do
            wbmgt decode "$bmg_file" --dest "$WORK_DIR/temp_msg.txt" --quiet --overwrite
            
            perl -pi -e 's/Daisy \(Schwarz\/Türkis\)/\\u{f0a2,f0a3,f0a4,f0a5,f0a4} (\\u{f0a0} Minecraft)/g' "$WORK_DIR/temp_msg.txt"
            perl -pi -e 's/Mach-Bike/\\u{f0aa} \\c{yor4}KFC\\c{off}-\\c{yor2}Mofa/g' "$WORK_DIR/temp_msg.txt"
            perl -pi -e 's/TheBeefBai/\\u{f0a1} heyFordy/g' "$WORK_DIR/temp_msg.txt"
            
            wbmgt encode "$WORK_DIR/temp_msg.txt" --dest "$bmg_file" --quiet --overwrite
            rm "$WORK_DIR/temp_msg.txt"
        done
        
        wszst create "$WORK_DIR/temp_szs" --dest "$szs_file" --overwrite --quiet
        rm -rf "$WORK_DIR/temp_szs"
    done
}

echo "📦 Processing MASTER Release (RetroRewind.zip)..."
wget -q "$BASE_URL/RetroRewind.zip" -O "$WORK_DIR/RetroRewind.zip"
unzip -q "$WORK_DIR/RetroRewind.zip" -d "$WORK_DIR/master"

mkdir -p "$WORK_DIR/master/RetroRewind6"
echo "$VERSION" > "$WORK_DIR/master/RetroRewind6/version.txt"

echo "   Applying patches..."
apply_patches "$WORK_DIR/master/RetroRewind6"

cd "$WORK_DIR/master"
zip -r -q "$ROOT_DIR/Fordy-RR-${VERSION}.zip" .

if [ -d "RetroRewind6/Language" ]; then
    find RetroRewind6/Language -name "*.szs" -exec zip -q "$ROOT_DIR/LANG_ONLY-Fordy-RR-${VERSION}.zip" {} +
fi

cd "$ROOT_DIR"
echo "✅ Created Fordy-RR-${VERSION}.zip and LANG_ONLY archive"

MAJOR_MINOR=$(echo "$VERSION" | cut -d. -f1-2)
MAX_PATCH=$(echo "$VERSION" | cut -d. -f3)

echo "🔄 Starting Update Loop for ${MAJOR_MINOR}.x..."

for ((i=0; i<=MAX_PATCH; i++)); do
    CURRENT_VER="${MAJOR_MINOR}.${i}"
    echo "------------------------------------------------"
    echo "Processing Update Version: $CURRENT_VER"
    
    TARGET_ZIP_NAME="UPDATE-Fordy-RR-${CURRENT_VER}.zip"
    DL_SUCCESS=false
    
    if wget -q "$BASE_URL/${CURRENT_VER}.zip" -O "$WORK_DIR/update_src.zip"; then
        DL_SUCCESS=true
    elif [ "$i" -eq 0 ] && wget -q "$BASE_URL/${MAJOR_MINOR}.zip" -O "$WORK_DIR/update_src.zip"; then
        echo "   Found via fallback: ${MAJOR_MINOR}.zip"
        DL_SUCCESS=true
    fi
    
    if [ "$DL_SUCCESS" = false ]; then
        echo "   ❌ Source zip not found on server. Skipping."
        continue
    fi
    
    rm -rf "$WORK_DIR/temp_update"
    mkdir -p "$WORK_DIR/temp_update"
    unzip -q "$WORK_DIR/update_src.zip" -d "$WORK_DIR/temp_update"
    
    mkdir -p "$WORK_DIR/temp_update/RetroRewind6"
    echo "$CURRENT_VER" > "$WORK_DIR/temp_update/RetroRewind6/version.txt"
    
    echo "   Attempting to patch files..."
    apply_patches "$WORK_DIR/temp_update/RetroRewind6"
    
    cd "$WORK_DIR/temp_update"
    zip -r -q "$ROOT_DIR/$TARGET_ZIP_NAME" .
    cd "$ROOT_DIR"
    
    echo "✅ Created $TARGET_ZIP_NAME"
    rm "$WORK_DIR/update_src.zip"
done

echo "🎉 All builds complete."