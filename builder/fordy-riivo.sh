#!/bin/bash

# Exit immediately on error
set -e

VERSION="$1"

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

echo "Starting build for version: $VERSION"

# Prepare clean workspace
rm -rf workdir
mkdir -p workdir

# Download RetroRewind release
echo "Downloading RetroRewind..."
wget -q http://update.rwfc.net:8000/RetroRewind/zip/RetroRewind.zip -O workdir/RetroRewind.zip

# Extract archive
echo "Unzipping archive..."
unzip -q workdir/RetroRewind.zip -d workdir/content

# Define target path
TARGET_DIR="workdir/content/RetroRewind6/Language/GER"

# Verify target exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Target directory $TARGET_DIR not found."
  exit 1
fi

# Process all SZS files
find "$TARGET_DIR" -name "*.szs" | while read szs_file; do
  echo "Processing: $szs_file"
  
  # Extract SZS contents
  wszst extract "$szs_file" --dest "workdir/temp_szs" --quiet --overwrite
  
  # Process BMG files inside SZS
  find "workdir/temp_szs" -name "*.bmg" | while read bmg_file; do
    echo "  Patching BMG: $bmg_file"
    
    # Decode BMG to text
    wbmgt decode "$bmg_file" --dest "workdir/temp_msg.txt" --quiet --overwrite
    
    # Replace 'Daisy' with 'Steve' (whole word only)
    perl -pi -e 's/\bDaisy\b/Steve/g' "workdir/temp_msg.txt"
    
    # Replace 'Mach-Bike' with 'KFC-Mofa'
    perl -pi -e 's/Mach-Bike/KFC-Mofa/g' "workdir/temp_msg.txt"
    
    # Encode text back to BMG (Force overwrite)
    wbmgt encode "workdir/temp_msg.txt" --dest "$bmg_file" --quiet --overwrite
    
    # Remove temp text file
    rm "workdir/temp_msg.txt"
  done
  
  # Repack SZS
  wszst create "workdir/temp_szs" --dest "$szs_file" --overwrite --quiet
  
  # Cleanup temp SZS dir
  rm -rf "workdir/temp_szs"
done

# Create final release ZIP
echo "Creating final ZIP..."
cd workdir/content
ZIP_NAME="Fordy-RR-${VERSION}.zip"
zip -r -q "../../$ZIP_NAME" .
cd ../..

echo "Build complete: $ZIP_NAME"
echo "artifact_path=$ZIP_NAME" >> $GITHUB_OUTPUT