#!/usr/bin/env bash
# =============================================================================
#  Bejeweled Twist compatibility patch — Linux / SteamOS (Proton) edition
# -----------------------------------------------------------------------------
#  Applies the OS-independent file patches (1-byte exe patch + compat.cfg
#  resolution unlock). The graphics/runtime side is handled by Proton itself —
#  see the printed instructions at the end. Contains NO game binaries.
#
#  Usage:   ./apply-fix.sh            (auto-detects the Steam install)
#           ./apply-fix.sh "/path/to/steamapps/common/Bejeweled Twist"
# =============================================================================
set -euo pipefail

STOCK_SHA="45a325f4d08b7f60ddb5054171c8a024ac3ffffd0efe5150f9c5abd2225faafd"
PATCHED_SHA="27d5524d122fc2c447f7519a247c8a0b2eba44790865a55691d27d23949379cf"
OFFSET=$((0x1D91DB))

find_game() {
  if [[ -n "${1:-}" ]]; then printf '%s' "$1"; return; fi
  local p
  for p in \
    "$HOME/.steam/steam/steamapps/common/Bejeweled Twist" \
    "$HOME/.local/share/Steam/steamapps/common/Bejeweled Twist" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Bejeweled Twist"; do
    [[ -f "$p/BejeweledTwist.exe" ]] && { printf '%s' "$p"; return; }
  done
}

GAME="$(find_game "${1:-}")"
if [[ -z "$GAME" || ! -f "$GAME/BejeweledTwist.exe" ]]; then
  echo "ERROR: BejeweledTwist.exe not found. Pass the path, e.g.:"
  echo "       $0 '/home/deck/.steam/steam/steamapps/common/Bejeweled Twist'"
  exit 1
fi
EXE="$GAME/BejeweledTwist.exe"; CFG="$GAME/compat.cfg"
echo "==> Game: $GAME"

# --- verify version ----------------------------------------------------------
sha="$(sha256sum "$EXE" | cut -d' ' -f1)"
if   [[ "$sha" == "$PATCHED_SHA" ]]; then echo "    exe already patched"
elif [[ "$sha" == "$STOCK_SHA"   ]]; then :
else echo "ERROR: unrecognized BejeweledTwist.exe ($sha); this targets v1.0.3.7482"; exit 1; fi

# --- backup ------------------------------------------------------------------
mkdir -p "$GAME/_original_backup"
[[ -f "$GAME/_original_backup/BejeweledTwist.exe" ]] || cp "$EXE" "$GAME/_original_backup/"
[[ -f "$GAME/_original_backup/compat.cfg"          ]] || cp "$CFG" "$GAME/_original_backup/"
echo "    backed up originals to _original_backup/"

# --- patch exe (1 byte: JNZ->JMP, video-card check bypass) -------------------
cur="$(dd if="$EXE" bs=1 skip=$OFFSET count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
if   [[ "$cur" == "eb" ]]; then echo "    exe byte already patched"
elif [[ "$cur" == "75" ]]; then
  printf '\xeb' | dd of="$EXE" bs=1 seek=$OFFSET count=1 conv=notrunc status=none
  echo "    patched exe: offset 0x$(printf '%X' $OFFSET) 0x75 -> 0xEB"
else echo "ERROR: unexpected byte 0x$cur at offset; aborting"; exit 1; fi

# --- patch compat.cfg (comment out the two VRAM gates; idempotent) ----------
perl -0777 -pi -e 's{(?<!/\*)(if \(compat_AppVidMemory < (?:60|92)\)\s*\n\s*return false;)}{/*$1*/}g' "$CFG"
echo "    compat.cfg VRAM gates commented (High/Ultra unlocked)"

cat <<'EOF'

File patches applied. Now configure Proton in Steam.

  The Windows fix works by routing this game through WineD3D (D3D -> OpenGL),
  which also makes touch input behave. On Proton, WineD3D IS built in - you just
  force that path instead of DXVK. So there are NO wrapper DLLs to copy here.

  1. Library > right-click Bejeweled Twist > Properties > Compatibility >
     tick "Force the use of a specific Steam Play compatibility tool"
     and choose the latest Proton (or GE-Proton if you have it).

  2. Properties > General > Launch Options, set:

         PROTON_USE_WINED3D=1 %command%

     (forces Proton's built-in wined3d/OpenGL path - the direct equivalent of the
      Windows WineD3D fix. This is the primary step, not a fallback.)

  3. Launch the game. In Options, enable 3D acceleration / choose High or Ultra.

  If it launched before but black-screened, its Wine prefix may hold a stale bad
  3D verdict - reset it once with:  rm -rf ~/.steam/steam/steamapps/compatdata/3560
  then relaunch (rebuilds the prefix fresh).

  NOTE: this SteamOS path mirrors the confirmed Windows fix but has not been
  verified on a specific Steam Deck here - if it misbehaves, report what you see.

Uninstall: restore files from _original_backup/ (or re-run Steam's "Verify integrity").
EOF
