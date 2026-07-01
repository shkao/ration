#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFTBAR_PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/.swiftbar-plugins}"
HELPER_DIR="$HOME/.octopace-helpers"

mkdir -p "$SWIFTBAR_PLUGIN_DIR" "$HELPER_DIR"

cp "$SCRIPT_DIR/octopace.5m.sh" "$SWIFTBAR_PLUGIN_DIR/octopace.5m.sh"
cp "$SCRIPT_DIR/helpers/octopace-login.sh" "$HELPER_DIR/octopace-login.sh"
chmod +x "$SWIFTBAR_PLUGIN_DIR/octopace.5m.sh" "$HELPER_DIR/octopace-login.sh"

echo "Installed:"
echo "  Plugin: $SWIFTBAR_PLUGIN_DIR/octopace.5m.sh"
echo "  Helper: $HELPER_DIR/octopace-login.sh"
echo
echo "In SwiftBar > Preferences > Plugins, set the Plugin Folder to:"
echo "  $SWIFTBAR_PLUGIN_DIR"
echo
echo "Note: only octopace.5m.sh belongs in that folder. SwiftBar treats every"
echo "executable file in the plugin folder as its own plugin, so the login"
echo "helper is installed elsewhere (~/.octopace-helpers) on purpose."
