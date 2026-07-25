#!/bin/bash

# Configuration
PLUGIN_DIR="$HOME/Documents/SwiftBar_Plugins"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="agy_usage.30s.py"
BASH_SCRIPT="get_agy_usage.sh"

echo "🚀 Starting SwiftBar and Agy Widget Setup..."

# 1. Install SwiftBar if not installed
if ! osascript -e 'id of application "SwiftBar"' &> /dev/null; then
    echo "📦 SwiftBar is not installed. Attempting to install via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install --cask swiftbar
    else
        echo "❌ Homebrew is not installed. Please install Homebrew or manually download SwiftBar."
        exit 1
    fi
else
    echo "✅ SwiftBar is already installed."
fi

# 2. Create Plugin Directory
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "📁 Creating SwiftBar plugins directory at $PLUGIN_DIR"
    mkdir -p "$PLUGIN_DIR"
else
    echo "✅ Plugin directory already exists at $PLUGIN_DIR"
fi

# 3. Configure SwiftBar to use this directory
echo "⚙️ Configuring SwiftBar to use the plugin directory..."
defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGIN_DIR"

# 4. Copy scripts to the Plugin Directory
echo "📋 Copying scripts to $PLUGIN_DIR..."
cp "$CURRENT_DIR/$PYTHON_SCRIPT" "$PLUGIN_DIR/"
cp "$CURRENT_DIR/$BASH_SCRIPT" "$PLUGIN_DIR/"

# Make sure they are executable
chmod +x "$PLUGIN_DIR/$PYTHON_SCRIPT"
chmod +x "$PLUGIN_DIR/$BASH_SCRIPT"

# 5. Update the path in the Python script dynamically
echo "🔧 Updating script path inside the python plugin..."
# We use python to safely replace the path string
python3 -c "
import sys
file_path = '$PLUGIN_DIR/$PYTHON_SCRIPT'
with open(file_path, 'r') as f:
    content = f.read()
content = content.replace('SCRIPT_DIR = \"$CURRENT_DIR\"', f'SCRIPT_DIR = \"{sys.argv[1]}\"')
with open(file_path, 'w') as f:
    f.write(content)
" "$PLUGIN_DIR"

# 6. Open SwiftBar (or restart it to pick up changes)
echo "🔄 Starting SwiftBar..."
killall SwiftBar 2>/dev/null
sleep 1
open -a SwiftBar

echo "🎉 Setup complete! The widget should now appear in your menu bar."
