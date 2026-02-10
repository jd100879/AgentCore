#!/bin/bash
# Cross-platform file/folder picker
# Works on Mac (AppleScript) and Windows (PowerShell)

set -euo pipefail

PICKER_TYPE="${1:-folder}"  # folder or file

# Detect OS
get_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "mac"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "linux"
    fi
}

# Mac file picker using AppleScript
mac_picker() {
    local picker_type="$1"

    if [ "$picker_type" = "folder" ]; then
        osascript <<EOF
set chosenFolder to choose folder with prompt "Select project folder:"
POSIX path of chosenFolder
EOF
    else
        osascript <<EOF
set chosenFile to choose file with prompt "Select file:"
POSIX path of chosenFile
EOF
    fi
}

# Windows file picker using PowerShell
windows_picker() {
    local picker_type="$1"

    if [ "$picker_type" = "folder" ]; then
        powershell.exe -Command "
            Add-Type -AssemblyName System.Windows.Forms
            \$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            \$dialog.Description = 'Select project folder'
            \$dialog.ShowNewFolderButton = \$true
            \$result = \$dialog.ShowDialog()
            if (\$result -eq [System.Windows.Forms.DialogResult]::OK) {
                Write-Output \$dialog.SelectedPath
            }
        " | tr -d '\r'
    else
        powershell.exe -Command "
            Add-Type -AssemblyName System.Windows.Forms
            \$dialog = New-Object System.Windows.Forms.OpenFileDialog
            \$dialog.Title = 'Select file'
            \$result = \$dialog.ShowDialog()
            if (\$result -eq [System.Windows.Forms.DialogResult]::OK) {
                Write-Output \$dialog.FileName
            }
        " | tr -d '\r'
    fi
}

# Fallback: fzf-based directory browser
fzf_picker() {
    local picker_type="$1"
    local start_dir="${2:-$HOME}"

    if ! command -v fzf &> /dev/null; then
        echo "Error: fzf not available for fallback picker" >&2
        return 1
    fi

    if [ "$picker_type" = "folder" ]; then
        # Directory picker with fzf
        find "$start_dir" -maxdepth 5 -type d 2>/dev/null | \
            fzf --prompt="Select folder > " \
                --height=60% \
                --border=rounded \
                --preview="ls -lah {}" \
                --preview-window=right:50%
    else
        # File picker with fzf
        find "$start_dir" -maxdepth 5 -type f 2>/dev/null | \
            fzf --prompt="Select file > " \
                --height=60% \
                --border=rounded \
                --preview="head -100 {}" \
                --preview-window=right:50%
    fi
}

# Main picker function
pick() {
    local os=$(get_os)
    local result=""

    case "$os" in
        mac)
            result=$(mac_picker "$PICKER_TYPE" 2>/dev/null || true)
            ;;
        windows)
            result=$(windows_picker "$PICKER_TYPE" 2>/dev/null || true)
            ;;
        *)
            result=$(fzf_picker "$PICKER_TYPE" "${2:-$HOME}" 2>/dev/null || true)
            ;;
    esac

    # Fallback to fzf if native picker failed
    if [ -z "$result" ] && command -v fzf &> /dev/null; then
        result=$(fzf_picker "$PICKER_TYPE" "${2:-$HOME}" 2>/dev/null || true)
    fi

    # Output the result
    if [ -n "$result" ]; then
        # Clean up path (remove trailing slashes, quotes, etc.)
        result=$(echo "$result" | sed 's/\/$//' | tr -d '\r\n')
        echo "$result"
    fi
}

pick "$@"
