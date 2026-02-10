#!/bin/bash

# Exit immediately on error
set -e

VERSION="$1"
BASE_URL="http://update.rwfc.net:8000/RetroRewind/zip"

# Set absolute paths for reliable workspace handling
ROOT_DIR=$(pwd)
WORK_DIR="$ROOT_DIR/workdir"

# Validate version input
if [ -z "$VERSION" ]; then
  echo "Error: No version provided."
  exit 1
fi

# Ensure necessary tools are available
if ! command -v wszst &> /dev/null || ! command -v wbmgt &> /dev/null; then
    echo "Error: wszst or wbmgt not found in PATH"
    exit 1
fi

echo "🚀 Starting build for version: $VERSION"

# Clean and create workspace
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Patch bmg files within szs containers
apply_patches() {
    local target_base="$1/Language"
    
    # Verify existence of language directory
    if [ ! -d "$target_base" ]; then
        echo "   ⚠️ No Language folder found. Skipping patches."
        return 0
    fi

    # Iterate through all szs files in language folders
    find "$target_base" -name "*.szs" | while read -r szs_file; do
        # Extract szs content
        wszst extract "$szs_file" --dest "$WORK_DIR/temp_szs" --quiet --overwrite
        
        # Search for bmg files inside extracted content
        find "$WORK_DIR/temp_szs" -name "*.bmg" | while read -r bmg_file; do
            # Convert bmg to editable text
            wbmgt decode "$bmg_file" --dest "$WORK_DIR/temp_msg.txt" --quiet --overwrite
            
            # Replace character and vehicle names using perl regex
            perl -pi -e 's/(?<!Baby )Daisy\b/\\c{yor3}Steve/g' "$WORK_DIR/temp_msg.txt"
            perl -pi -e 's/Mach-Bike/\\c{yor4}KFC\\c{off}-\\c{yor2}Mofa/g' "$WORK_DIR/temp_msg.txt"
            
            # Convert text back to bmg format
            wbmgt encode "$WORK_DIR/temp_msg.txt" --dest "$bmg_file" --quiet --overwrite
            rm "$WORK_DIR/temp_msg.txt"
        done
        
        # Rebuild szs file
        wszst create "$WORK_DIR/temp_szs" --dest "$szs_file" --overwrite --quiet
        rm -rf "$WORK_DIR/temp_szs"
    done
}

# Download and extract main release
echo "📦 Processing MASTER Release (RetroRewind.zip)..."
wget -q "$BASE_URL/RetroRewind.zip" -O "$WORK_DIR/RetroRewind.zip"
unzip -q "$WORK_DIR/RetroRewind.zip" -d "$WORK_DIR/master"

# Update version tracking file
mkdir -p "$WORK_DIR/master/RetroRewind6"
echo "$VERSION" > "$WORK_DIR/master/RetroRewind6/version.txt"

# Run patching logic on master files
echo "   Applying text patches to all languages..."
apply_patches "$WORK_DIR/master/RetroRewind6"

# Repackage modified master release
cd "$WORK_DIR/master"
zip -r -q "$ROOT_DIR/Fordy-RR-${VERSION}.zip" .
cd "$ROOT_DIR"
echo "✅ Created Fordy-RR-${VERSION}.zip"

# Calculate update versions
MAJOR_MINOR=$(echo "$VERSION" | cut -d. -f1-2)
MAX_PATCH=$(echo "$VERSION" | cut -d. -f3)

echo "🔄 Starting Update Loop for ${MAJOR_MINOR}.x..."

# Loop through patch versions for update packages
for ((i=0; i<=MAX_PATCH; i++)); do
    CURRENT_VER="${MAJOR_MINOR}.${i}"
    echo "------------------------------------------------"
    echo "Processing Update Version: $CURRENT_VER"
    
    TARGET_ZIP_NAME="UPDATE-Fordy-RR-${CURRENT_VER}.zip"
    DL_SUCCESS=false
    
    # Attempt to download update zip
    if wget -q "$BASE_URL/${CURRENT_VER}.zip" -O "$WORK_DIR/update_src.zip"; then
        DL_SUCCESS=true
    elif [ "$i" -eq 0 ] && wget -q "$BASE_URL/${MAJOR_MINOR}.zip" -O "$WORK_DIR/update_src.zip"; then
        echo "   Found via fallback: ${MAJOR_MINOR}.zip"
        DL_SUCCESS=true
    fi
    
    # Skip if download failed
    if [ "$DL_SUCCESS" = false ]; then
        echo "   ❌ Source zip not found on server. Skipping."
        continue
    fi
    
    # Extract update content
    rm -rf "$WORK_DIR/temp_update"
    mkdir -p "$WORK_DIR/temp_update"
    unzip -q "$WORK_DIR/update_src.zip" -d "$WORK_DIR/temp_update"
    
    # Sync version file
    mkdir -p "$WORK_DIR/temp_update/RetroRewind6"
    echo "$CURRENT_VER" > "$WORK_DIR/temp_update/RetroRewind6/version.txt"
    
    # Apply patches to update files
    echo "   Attempting to patch files..."
    apply_patches "$WORK_DIR/temp_update/RetroRewind6"
    
    # Create the update zip package
    cd "$WORK_DIR/temp_update"
    zip -r -q "$ROOT_DIR/$TARGET_ZIP_NAME" .
    cd "$ROOT_DIR"
    
    echo "✅ Created $TARGET_ZIP_NAME"
    rm "$WORK_DIR/update_src.zip"
done

echo "🎉 All builds complete."