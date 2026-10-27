#!/bin/bash
# Double-click this file in Finder to start the LfS Web Viewer.
# It opens a Terminal window (leave it open while you use the viewer) and your browser.
# To stop the viewer, close that Terminal window or press Ctrl-C in it.

cd "$(dirname "$0")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 isn't installed. Install it from https://www.python.org/downloads/ and try again."
  read -r -p "Press Return to close."
  exit 1
fi

python3 lfs_viewer.py "$@"
echo
read -r -p "The viewer has stopped. Press Return to close this window."
