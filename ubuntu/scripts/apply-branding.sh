#!/bin/bash
# =============================================================================
# apply-branding.sh
# Substitutes values from distro.conf into all phase documents and build files.
#
# Usage:
#   ./scripts/apply-branding.sh              # dry run — shows what would change
#   ./scripts/apply-branding.sh --apply      # apply changes in place
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$ROOT_DIR/distro.conf"

# ── Load config ──────────────────────────────────────────────────────────────
if [ ! -f "$CONF" ]; then
    echo "ERROR: $CONF not found. Run this from the repo root."
    exit 1
fi
source "$CONF"

DRY_RUN=true
if [ "${1:-}" = "--apply" ]; then
    DRY_RUN=false
fi

# ── Define substitutions ─────────────────────────────────────────────────────
# Format: "PLACEHOLDER|VALUE"
# Placeholders are the defaults used in the plan documents.
declare -a SUBS=(
    "MyDistro|${DISTRO_NAME}"
    "mydistro|${DISTRO_ID}"
    "orbital|${DISTRO_CODENAME_ID}"
    "1\.0|${DISTRO_VERSION}"
    "https://mydistro\.example\.com/support|${DISTRO_SUPPORT_URL}"
    "https://mydistro\.example\.com/issues|${DISTRO_BUGS_URL}"
    "https://mydistro\.example\.com/notes|${DISTRO_NOTES_URL}"
    "https://mydistro\.example\.com|${DISTRO_URL}"
    "releases@mydistro\.example\.com|${DISTRO_SIGNING_EMAIL}"
    "noble|${UBUNTU_CODENAME}"
    "#1a1a2e|${COLOR_BG_DARK}"
    "#16213e|${COLOR_BG_MID}"
    "#4a90d9|${COLOR_ACCENT}"
    "#e0e0e0|${COLOR_TEXT_PRIMARY}"
    "#888888|${COLOR_TEXT_SECONDARY}"
    "#2a2a4a|${COLOR_BUTTON_BG}"
    "KERNEL_VERSION=\"7\.1\"|KERNEL_VERSION=\"${KERNEL_MAINLINE_VERSION}\""
    "trixie|${DEBIAN_CODENAME}"
)

# Only substitute pkg repo URL if one is set
if [ -n "${DISTRO_PKG_REPO_URL:-}" ]; then
    SUBS+=("https://pkg\.mydistro\.example\.com/apt|${DISTRO_PKG_REPO_URL}")
fi

# ── Files to process ─────────────────────────────────────────────────────────
mapfile -t TARGET_FILES < <(find "$ROOT_DIR" \
    \( -name "*.md" -o -name "*.conf" -o -name "*.sh" -o -name "*.yaml" \
       -o -name "*.yml" -o -name "*.xml" -o -name "*.list" \
       -o -name "*.css" -o -name "*.qml" -o -name "themerc" \
       -o -name "lb-config" -o -name "Makefile" \) \
    -not -path "*/build/*" \
    -not -path "*/.git/*" \
    -not -name "distro.conf" \
    -not -name "apply-branding.sh" \
    | sort)

# ── Apply substitutions ──────────────────────────────────────────────────────
CHANGED=0

for file in "${TARGET_FILES[@]}"; do
    rel="${file#$ROOT_DIR/}"

    # Build the sed expression using | as delimiter to avoid conflicts with / in URLs
    SED_EXPR=""
    for sub in "${SUBS[@]}"; do
        from="${sub%%|*}"
        to="${sub##*|}"
        # Escape pipe characters in the replacement value (unlikely but safe)
        to_escaped="${to//|/\\|}"
        SED_EXPR="${SED_EXPR}s|${from}|${to_escaped}|g;"
    done

    # Check if file would change
    NEW_CONTENT=$(sed -e "$SED_EXPR" "$file")
    ORIG_CONTENT=$(cat "$file")

    if [ "$NEW_CONTENT" != "$ORIG_CONTENT" ]; then
        if $DRY_RUN; then
            echo "[WOULD CHANGE] $rel"
            diff <(echo "$ORIG_CONTENT") <(echo "$NEW_CONTENT") | head -20
            echo "---"
        else
            echo "[UPDATING] $rel"
            echo "$NEW_CONTENT" > "$file"
        fi
        ((CHANGED++)) || true
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if $DRY_RUN; then
    echo "Dry run complete. $CHANGED file(s) would be updated."
    echo "Run with --apply to make changes:"
    echo "  ./scripts/apply-branding.sh --apply"
else
    echo "Done. $CHANGED file(s) updated."
fi
