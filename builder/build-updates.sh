#!/bin/bash
# Builds RetroRewind updates, patches text in .szs/.bmg and injects MyStuff

TARGET_VERSION="$1"
REPO_ROOT="$2"
VERSION_URL="http://update.rwfc.net:8000/RetroRewind/RetroRewindVersion.txt"
WORK_DIR="build_tmp"

# Get Base Version (e.g. 6.5.4 -> 6.5)
BASE_VERSION=$(echo "$TARGET_VERSION" | cut -d. -f1-2)

echo "🎯 Target: $TARGET_VERSION (Base Series: $BASE_VERSION)"

# Fetch Version List
curl -s "$VERSION_URL" > versions.txt

# Clean workspace
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Process all versions starting with Base Version
grep "^$BASE_VERSION" versions.txt | while read -r LINE; do
    VER=$(echo "$LINE" | awk '{print $1}')
    URL=$(echo "$LINE" | awk '{print $2}')
    ZIP_NAME=$(basename "$URL")
    
    echo "------------------------------------------------"
    echo "🔨 Processing Version: $VER"
    
    # 1. Download & Extract
    wget -q "$URL" -O "$WORK_DIR/$ZIP_NAME"
    unzip -q -o "$WORK_DIR/$ZIP_NAME" -d "$WORK_DIR/extract_$VER"
    
    # Identify Root
    if [ -d "$WORK_DIR/extract_$VER/RetroRewind6" ]; then
        RR_ROOT="$WORK_DIR/extract_$VER/RetroRewind6"
    else
        RR_ROOT="$WORK_DIR/extract_$VER"
    fi
    
    # 2. Inject MyStuff
    echo "📂 Injecting MyStuff..."
    mkdir -p "$RR_ROOT/MyStuff"
    if [ -d "$REPO_ROOT/.mystuff" ]; then
        cp -r "$REPO_ROOT/.mystuff/"* "$RR_ROOT/MyStuff/"
    else
        # Create dummy if missing to ensure folder exists
        touch "$RR_ROOT/MyStuff/.gitkeep"
    fi
    
    # 3. Patch version.xml
    XML_FILE="$RR_ROOT/version.xml"
    if [ -f "$XML_FILE" ]; then
        echo "🔧 Fixing version.xml to $VER..."
        sed -i "s|<version>.*</version>|<version>$VER</version>|g" "$XML_FILE"
    fi
    
    # 4. Text Modifications (SZS -> BMG)
    COMMON_ASSETS="$RR_ROOT/Assets/CommonAssets.szs"
    
    if [ -f "$COMMON_ASSETS" ]; then
        echo "📝 Modifying Text in CommonAssets.szs..."
        
        # Extract SZS
        wszst extract "$COMMON_ASSETS" --dest "$WORK_DIR/common_tmp" --quiet
        
        # Decode BMG files, Replace Text, Encode
        find "$WORK_DIR/common_tmp" -name "*.bmg" | while read -r BMG_FILE; do
            TXT_FILE="${BMG_FILE%.*}.txt"
            
            # Decode
            wbmgt decode "$BMG_FILE" --dest "$TXT_FILE" --quiet
            
            # Replace
            sed -i 's/Mach-Bike/KFC-Mofa/g' "$TXT_FILE"
            sed -i 's/Daisy/Steve/g' "$TXT_FILE"
            
            # Encode back
            wbmgt encode "$TXT_FILE" --dest "$BMG_FILE" --quiet
            rm "$TXT_FILE"
        done
        
        # Create SZS
        wszst create "$WORK_DIR/common_tmp" --dest "$COMMON_ASSETS" --quiet
        rm -rf "$WORK_DIR/common_tmp"
    else
        echo "⚠️ CommonAssets.szs not found in this zip. Skipping text mods."
    fi

    # 5. Create Packages
    cd "$WORK_DIR/extract_$VER"
    
    # A. UPDATE Zip (Full content of this version patched)
    echo "📦 Zipping UPDATE-Fordy-RR-$VER.zip..."
    zip -q -r "../../UPDATE-Fordy-RR-$VER.zip" .
    
    # B. Target Version Specials
    if [ "$VER" == "$TARGET_VERSION" ]; then
        echo "🏆 Creating Main Release Artifacts..."
        
        # Main Full Zip
        cp "../../UPDATE-Fordy-RR-$VER.zip" "../../Fordy-RR-$VER.zip"
        
        # Patch Only Zip (Modified files only)
        echo "🧩 Creating PATCH_ONLY zip..."
        mkdir -p "../../patch_temp/RetroRewind6/Assets"
        
        # Copy modified files
        [ -f "$RR_ROOT/version.xml" ] && cp "$RR_ROOT/version.xml" "../../patch_temp/RetroRewind6/"
        [ -d "$RR_ROOT/MyStuff" ] && cp -r "$RR_ROOT/MyStuff" "../../patch_temp/RetroRewind6/"
        [ -f "$RR_ROOT/Assets/CommonAssets.szs" ] && cp "$RR_ROOT/Assets/CommonAssets.szs" "../../patch_temp/RetroRewind6/Assets/"
        
        cd "../../patch_temp"
        zip -q -r "../../Fordy-RR-$VER-PATCH_ONLY.zip" .
        cd ..
        rm -rf "patch_temp"
        
        # Back to extract dir
        cd "$WORK_DIR/extract_$VER"
    fi
    
    cd ../..
    rm -rf "$WORK_DIR/extract_$VER"
    rm "$WORK_DIR/$ZIP_NAME"
    
done

echo "✅ All tasks finished."