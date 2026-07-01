#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
echo "Signing in to GitHub for Octopace..."
echo
gh auth login --hostname github.com --git-protocol https --web
echo
echo "Done — Octopace will pick this up on its next refresh."
read -r -p "Press Enter to close this window... "
