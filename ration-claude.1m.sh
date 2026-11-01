#!/bin/bash
# Show Claude as a separate SwiftBar item when the split layout is enabled.

main() {
  local plugin_dir
  plugin_dir="$(cd "$(dirname "$0")" && pwd)"
  RATION_SPLIT_ROLE=claude exec "${plugin_dir}/ration.1m.sh" "$@"
}

main "$@"
