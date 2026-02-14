#!/bin/bash
# Stub script to satisfy hook requirement
case "$1" in
  whoami)
    echo "TopazDeer"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
