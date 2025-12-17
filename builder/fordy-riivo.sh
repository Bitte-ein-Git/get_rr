#!/bin/bash

# Exit immediately on error
set -e

VERSION="$1"
BASE_URL="http://update.rwfc.net:8000/RetroRewind/zip"

# Validate version argument
if [ -z "$VERSION" ]; then
  echo "Error: No version provided."
  exit 1
fi

# Check for tools in PATH
if ! command -v wszst &> /dev/null || ! command -v wbmgt &> /dev/null; then
    echo "Error: wszst or wbmgt not found in PATH"
    exit 1
fi

echo "🚀 Starting build for version: $VERSION"

# Setup workspace
rm -rf workdir
mkdir -p workdir

# Function to apply text patches
apply_patches() {
    local target_base="$1/Language/GER"
    
    # Check if GER folder exists (updates might not have it)
    if [ ! -d "$target_base" ]; then
        echo "   ⚠️ No GER language folder found in this zip. Skipping patches."
        return 0
    fi

    # Process all SZS files
    find "$target_base" -name "*.szs" | while read szs_file; do
        # Extract SZS contents
        wszst extract "$szs_file" --dest "workdir/temp_szs" --quiet --overwrite
        
        # Process BMG files inside SZS
        find "workdir/temp_szs" -name "*.bmg" | while read bmg_file; do
            # Decode BMG to text
            wbmgt decode "$bmg_file" --dest "workdir/temp_msg.txt" --quiet --overwrite
            
            # Apply Replacements
            perl -pi -e 's/\bDaisy\b/Steve/g' "workdir/temp_msg.txt"
            perl -pi -e 's/Mach-Bike/KFC-Mofa/g' "workdir/temp_msg.txt"
            
            # Encode text back to BMG
            wbmgt encode "workdir/temp_msg.txt" --dest "$bmg_file" --quiet --overwrite
            rm "workdir/temp_msg.txt"
        done
        
        # Repack SZS
        wszst create "workdir/temp_szs" --dest "$szs_file" --overwrite --quiet
        rm -rf "workdir/temp_szs"
    done
}

# ==============================================================================
# 1. PROCESS MASTER RELEASE (RetroRewind.zip)
# ==============================================================================
echo "📦 Processing MASTER Release (RetroRewind.zip)..."
wget -q "$BASE_URL/RetroRewind.zip" -O workdir/RetroRewind.zip
unzip -q workdir/RetroRewind.zip -d workdir/master

# Force update version.txt
mkdir -p "workdir/master/RetroRewind6"
echo "$VERSION" > "workdir/master/RetroRewind6/version.txt"

# Apply Patches
echo "   Applying text patches..."
apply_patches "workdir/master/RetroRewind6"

# Create Master Zip
cd workdir/master
zip -r -q "../../Fordy-RR-${VERSION}.zip" .
cd ../..
echo "✅ Created Fordy-RR-${VERSION}.zip"

# ==============================================================================
# 2. PROCESS UPDATE LOOP (All versions in this major release)
# ==============================================================================
MAJOR_MINOR=$(echo "$VERSION" | cut -d. -f1-2)
MAX_PATCH=$(echo "$VERSION" | cut -d. -f3)

echo "🔄 Starting Update Loop for ${MAJOR_MINOR}.x (0 to $MAX_PATCH)..."

for ((i=0; i<=MAX_PATCH; i++)); do
    CURRENT_VER="${MAJOR_MINOR}.${i}"
    echo "------------------------------------------------"
    echo "Processing Update Version: $CURRENT_VER"
    
    TARGET_ZIP_NAME="UPDATE-Fordy-RR-${CURRENT_VER}.zip"
    
    # Download Logic with Fallback for x.x.0
    DL_SUCCESS=false
    
    # Try Standard Format x.x.x.zip
    if wget -q "$BASE_URL/${CURRENT_VER}.zip" -O "workdir/update_src.zip"; then
        DL_SUCCESS=true
    # Try Short Format x.x.zip (only for .0 releases)
    elif [ "$i" -eq 0 ] && wget -q "$BASE_URL/${MAJOR_MINOR}.zip" -O "workdir/update_src.zip"; then
        echo "   Found via fallback: ${MAJOR_MINOR}.zip"
        DL_SUCCESS=true
    fi
    
    if [ "$DL_SUCCESS" = false ]; then
        echo "   ❌ Source zip not found on server. Skipping."
        continue
    fi
    
    # Extract
    rm -rf workdir/temp_update
    mkdir -p workdir/temp_update
    unzip -q "workdir/update_src.zip" -d "workdir/temp_update"
    
    # Force update version.txt (Create dir if missing)
    mkdir -p "workdir/temp_update/RetroRewind6"
    echo "$CURRENT_VER" > "workdir/temp_update/RetroRewind6/version.txt"
    
    # Apply Patches (Best Effort)
    echo "   Attempting to patch files..."
    apply_patches "workdir/temp_update/RetroRewind6"
    
    # Create Update Zip
    cd workdir/temp_update
    zip -r -q "../../$TARGET_ZIP_NAME" .
    cd ../..
    
    echo "✅ Created $TARGET_ZIP_NAME"
    rm workdir/update_src.zip
done

echo "🎉 All builds complete."