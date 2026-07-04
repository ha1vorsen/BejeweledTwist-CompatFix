# Bejeweled Twist — Modern Compatibility Fix

Makes Bejeweled Twist (Steam, v1.0.3.7482) run on modern Windows and SteamOS: fixes the "video card does not meet minimum requirements" error, the crash on startup, the locked resolution, and broken touch input. Graphics go through WineD3D (DirectDraw/D3D → OpenGL) rather than dgVoodoo, because dgVoodoo hijacks the cursor in fullscreen and breaks touchscreens.

You need the game owned and installed through Steam, Windows 10/11 (or SteamOS/Proton), and internet on first run to fetch WineD3D.

## Windows

Run `Run-Fix.bat` (or `powershell -ExecutionPolicy Bypass -File Apply-BejeweledTwistFix.ps1`), then launch from Steam. Add `-GamePath "..."` if the game isn't auto-detected. It's safe to re-run — do so after any Steam "Verify integrity", which reverts the patched files. `Uninstall-BejeweledTwistFix.ps1` restores stock.

## SteamOS / Steam Deck

Run `chmod +x apply-fix.sh && ./apply-fix.sh`, then force a recent Proton and set launch options to `PROTON_USE_WINED3D=1 %command%` (Proton's built-in equivalent of the Windows WineD3D wrapper — no extra DLLs). This path mirrors the Windows fix but hasn't been tested on an actual Deck.

## Notes

The package ships no game files, only patch instructions: a 1-byte exe edit (`0x1D91DB`: `0x75`→`0xEB`), two commented-out lines in `compat.cfg`, WineD3D downloaded from fdossena.com, and a couple of registry values. The exe is SHA-256 checked before patching and refuses unknown builds; originals are backed up to `_original_backup`. It targets v1.0.3.7482 and does not bypass Steam DRM.

Credits: video-card patch from cheez3d/popcap-patches; WineD3D by the Wine project, Windows build by Federico Dossena (fdossena.com).
