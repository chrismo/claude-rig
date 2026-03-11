#!/bin/bash
# Helper script to manage Claude Code JetBrains plugin blocks.
# Written by Claude! Clever, if it works.

JETBRAINS_DIR="$HOME/Library/Application Support/JetBrains"
PLUGIN_NAME="claude-code-jetbrains-plugin"

show_status() {
    echo "=== Claude Code Plugin Block Status ==="
    echo ""

    for ide_dir in "$JETBRAINS_DIR"/*; do
        [ -d "$ide_dir" ] || continue

        ide_name=$(basename "$ide_dir")
        plugin_path="$ide_dir/plugins/$PLUGIN_NAME"

        if [ -e "$plugin_path" ]; then
            if [ -d "$plugin_path" ]; then
                echo "❌ $ide_name: PLUGIN INSTALLED (directory)"
            elif [ -f "$plugin_path" ]; then
                # Check for uchg flag using stat
                if stat -f "%Sf" "$plugin_path" | grep -q "uchg"; then
                    echo "🛡️  $ide_name: BLOCKED (immutable file)"
                else
                    echo "⚠️  $ide_name: FILE EXISTS (not immutable)"
                fi
            fi
        fi
    done
    echo ""
}

block_ide() {
    local ide_version="$1"
    local ide_dir="$JETBRAINS_DIR/$ide_version"
    local plugins_dir="$ide_dir/plugins"
    local plugin_path="$plugins_dir/$PLUGIN_NAME"

    if [ ! -d "$ide_dir" ]; then
        echo "❌ IDE directory not found: $ide_dir"
        return 1
    fi

    echo "Blocking $ide_version..."

    # Create plugins directory if it doesn't exist
    mkdir -p "$plugins_dir"

    # Remove existing plugin if it's a directory
    if [ -d "$plugin_path" ]; then
        echo "  Removing existing plugin directory..."
        # Need to remove immutable flag first if set
        chflags -R nouchg "$plugin_path" 2>/dev/null
        rm -rf "$plugin_path"
    fi

    # Remove immutable flag if file already exists
    if [ -f "$plugin_path" ]; then
        chflags nouchg "$plugin_path" 2>/dev/null
    fi

    # Create immutable file block
    touch "$plugin_path"
    chmod 000 "$plugin_path"
    chflags uchg "$plugin_path"

    echo "✅ $ide_version blocked"
}

unblock_ide() {
    local ide_version="$1"
    local ide_dir="$JETBRAINS_DIR/$ide_version"
    local plugin_path="$ide_dir/plugins/$PLUGIN_NAME"

    if [ ! -e "$plugin_path" ]; then
        echo "❌ No block found for $ide_version"
        return 1
    fi

    echo "Unblocking $ide_version..."

    # Remove immutable flag
    chflags nouchg "$plugin_path"
    rm -f "$plugin_path"

    echo "✅ $ide_version unblocked"
}

block_all() {
    echo "=== Blocking all JetBrains IDEs ==="
    echo ""

    local found_any=false

    for ide_dir in "$JETBRAINS_DIR"/*; do
        [ -d "$ide_dir" ] || continue

        ide_name=$(basename "$ide_dir")

        # Skip non-IDE directories
        case "$ide_name" in
            PrivacyPolicy|bl|consentOptions|crl|IntelliJ|Pycharm|Rubymine)
                # Skip these - they're either not version-specific or lowercase variants
                continue
                ;;
        esac

        # Only process directories that look like versioned IDEs (contain a digit)
        if [[ "$ide_name" =~ [0-9] ]]; then
            block_ide "$ide_name"
            found_any=true
        fi
    done

    if [ "$found_any" = false ]; then
        echo "No JetBrains IDE installations found"
    fi

    echo ""
    show_status
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") [command] [args]

Commands:
    status                  Show current block status for all IDEs
    block <IDE-VERSION>     Block plugin for specific IDE (e.g., RubyMine2025.2)
    unblock <IDE-VERSION>   Unblock plugin for specific IDE
    block-all               Block all JetBrains IDEs found in JetBrains directory
    help                    Show this help message

Examples:
    $(basename "$0") status
    $(basename "$0") block RubyMine2025.2
    $(basename "$0") block PyCharm2025.2
    $(basename "$0") unblock RubyMine2025.2
    $(basename "$0") block-all

The blocks work by creating immutable zero-byte files at the plugin path,
preventing Claude Code from installing the plugin directory.

EOF
}

# Main command handler
case "${1:-status}" in
    status)
        show_status
        ;;
    block)
        if [ -z "$2" ]; then
            echo "❌ Error: IDE version required"
            echo "Usage: $0 block <IDE-VERSION>"
            exit 1
        fi
        block_ide "$2"
        echo ""
        show_status
        ;;
    unblock)
        if [ -z "$2" ]; then
            echo "❌ Error: IDE version required"
            echo "Usage: $0 unblock <IDE-VERSION>"
            exit 1
        fi
        unblock_ide "$2"
        echo ""
        show_status
        ;;
    block-all)
        block_all
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
