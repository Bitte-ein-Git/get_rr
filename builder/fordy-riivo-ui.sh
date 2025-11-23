#!/bin/bash

# Sofort beenden bei Fehler
set -e

VERSION="$1"
TAG_NAME="$2"

# Pfade zu den Tools
WSZST="./wszst/wszst"
WBMGT="./wszst/wbmgt"
WUJ5="./wszst/wuj5_src/wuj5.py"

if [ -z "$VERSION" ] || [ -z "$TAG_NAME" ]; then
  echo "Error: Missing arguments. Usage: ./script.sh <VERSION> <TAG>"
  exit 1
fi

# Check Basic Tools
if [ ! -f "$WSZST" ] || [ ! -f "$WBMGT" ]; then
  echo "Error: Local tools (wszst, wbmgt) not found in ./wszst/"
  exit 1
fi

# Check wuj5
if [ ! -f "$WUJ5" ]; then
    echo "Error: wuj5.py not found at $WUJ5. Ensure the repo was cloned."
    exit 1
fi

echo "Starting Precision UI Build: $VERSION ($TAG_NAME)"

# Clean & Prep
rm -rf workdir
mkdir -p workdir

# 1. Download
echo "Downloading RetroRewind..."
wget -q http://update.rwfc.net:8000/RetroRewind/zip/RetroRewind.zip -O workdir/RetroRewind.zip
unzip -q workdir/RetroRewind.zip -d workdir/content

TARGET_DIR="workdir/content/RetroRewind6/Language/GER"

# Helper function for JSON5 patching
patch_json_color() {
    # $1 = File, $2 = SearchColor, $3 = ReplaceColor
    # Use perl to replace carefully in JSON structure
    perl -pi -e "s/\"$2\"/\"$3\"/gi" "$1"
}


find "$TARGET_DIR" -name "*.szs" | while read szs_file; do
  FILENAME=$(basename "$szs_file")
  
  # UIAssets.szs -> Hauptmenü Buttons
  # Title.szs -> Titelscreen
  # MenuSingle/Multi.szs -> Menüs
  # Race.szs -> In-Game HUD
  # Alles andere (Strecken) überspringen für Layout-Edits, patchen aber Texte.
  
  IS_UI_FILE=false
  if [[ "$FILENAME" == "UIAssets.szs" ]] || \
     [[ "$FILENAME" == *"Title"* ]] || \
     [[ "$FILENAME" == *"Menu"* ]] || \
     [[ "$FILENAME" == *"Race"* ]] || \
     [[ "$FILENAME" == "homeBtn_G.szs" ]]; then
     IS_UI_FILE=true
  fi

  echo "Processing: $FILENAME (UI Mode: $IS_UI_FILE)"
  
  # Extract
  $WSZST extract "$szs_file" --dest "workdir/temp_szs" --quiet --overwrite
  
  # --- A. TEXTE (BMG) - Immer patchen (auch in Maps wenn vorhanden) ---
  find "workdir/temp_szs" -name "*.bmg" | while read bmg_file; do
    # echo "  [Text] Patching $bmg_file"
    $WBMGT decode "$bmg_file" --dest "workdir/temp_msg.txt" --quiet --overwrite
    perl -pi -e 's/\bDaisy\b/Steve/g' "workdir/temp_msg.txt"
    perl -pi -e 's/Mach-Bike/KFC-Mofa/g' "workdir/temp_msg.txt"
    $WBMGT encode "workdir/temp_msg.txt" --dest "$bmg_file" --quiet --overwrite
    rm "workdir/temp_msg.txt"
  done

  # --- B. LAYOUTS (BRLYT/BRLAN) - Nur in UI Files ---
  if [ "$IS_UI_FILE" = true ]; then
      find "workdir/temp_szs" -name "*.brlyt" -o -name "*.brlan" | while read lyt_file; do
        BASE_LYT=$(basename "$lyt_file")
        JSON_FILE="${lyt_file}.json5"
        
        # Decode
        python3 "$WUJ5" decode "$lyt_file" -o "$JSON_FILE"
        
        # --- Gezielte Änderungen ---
        
        # 1. Buttons (Dateinamen: button_*.brlyt/.brlan)
        if [[ "$BASE_LYT" == "button"* ]]; then
             echo "  [UI] Coloring Button: $BASE_LYT"
             patch_json_color "$JSON_FILE" "FFFFFFFF" "FFA500FF" # Weiß -> Orange
             patch_json_color "$JSON_FILE" "C0C0C0FF" "FFA500FF" # Hellgrau -> Orange
             patch_json_color "$JSON_FILE" "B0B0B0FF" "FFA500FF" # Grau -> Orange
             
             # Speziell für "W_m_base" (Der Button-Hintergrund oft)
        fi
        
        # 2. Andere UI Elemente (nur Weiß ersetzen, vorsichtig)
        if [[ "$BASE_LYT" != "button"* ]]; then
             # Wird später erweitert
             :
        fi

        # Encode back
        python3 "$WUJ5" encode "$JSON_FILE" -o "$lyt_file"
        rm "$JSON_FILE"
      done
  fi

  # Repack
  $WSZST create "workdir/temp_szs" --dest "$szs_file" --overwrite --quiet
  rm -rf "workdir/temp_szs"
done

# 3. Release
echo "Creating Release ZIP..."
cd workdir/content
ZIP_NAME="Fordy-RR-UI-Mod-${TAG_NAME}.zip"
zip -r -q "../../$ZIP_NAME" .
cd ../..

echo "artifact_path=$ZIP_NAME" >> $GITHUB_OUTPUT