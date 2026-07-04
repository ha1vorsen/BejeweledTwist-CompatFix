<#
    Uninstall-BejeweledTwistFix.ps1
    Reverts everything Apply-BejeweledTwistFix.ps1 changed and returns the game
    to its stock state. Prefers restoring the backup; if none exists it reverses
    the edits in place, so it works even on a machine that has no backup folder.
#>
[CmdletBinding()]
param([string]$GamePath)

$ErrorActionPreference = 'Stop'
$EXE_NAME = 'BejeweledTwist.exe'
$VCARD_OFFSET = 0x1D91DB
# wrapper files to remove: WineD3D set + any leftovers from an older dgVoodoo-based fix
$WRAPPER_FILES = @('ddraw.dll','d3d9.dll','d3d8.dll','wined3d.dll','D3DImm.dll','dgVoodoo.conf')
$PROGDATA = Join-Path $env:ProgramData 'PopCap Games\BejeweledTwist'
$REG_KEY  = 'HKCU:\Software\Steam\BejeweledTwist'

function Find-GamePath([string]$Explicit){
    if($Explicit){ return $Explicit }
    $c = @()
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -EA Stop).SteamPath -replace '/','\'
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if(Test-Path $vdf){ foreach($l in Get-Content $vdf){ if($l -match '"path"\s*"(.+?)"'){ $c += ($matches[1] -replace '\\\\','\') } } }
        $c += $steam
    } catch {}
    $c += 'C:\Games\Steam','C:\Program Files (x86)\Steam'
    foreach($lib in ($c | Select-Object -Unique)){ $p = Join-Path $lib 'steamapps\common\Bejeweled Twist'; if(Test-Path (Join-Path $p $EXE_NAME)){ return $p } }
    return $null
}

$GamePath = Find-GamePath $GamePath
if(-not $GamePath){ throw "Could not find the game. Re-run with -GamePath '<Bejeweled Twist folder>'." }
Write-Host "Game: $GamePath" -ForegroundColor Cyan
$bak = Join-Path $GamePath '_original_backup'

# 1. Restore exe + compat.cfg from backup, or reverse edits in place
foreach($f in @($EXE_NAME,'compat.cfg')){
    $target = Join-Path $GamePath $f; $b = Join-Path $bak $f
    if(Test-Path $b){ Copy-Item $b $target -Force; Write-Host "  restored $f from backup" -ForegroundColor Green }
}
if(-not (Test-Path (Join-Path $bak $EXE_NAME))){
    $exe = Join-Path $GamePath $EXE_NAME
    $by = [IO.File]::ReadAllBytes($exe)
    if($by[$VCARD_OFFSET] -eq 0xEB){ $by[$VCARD_OFFSET] = 0x75; [IO.File]::WriteAllBytes($exe,$by); Write-Host "  reversed exe byte patch in place" -ForegroundColor Green }
}
if(-not (Test-Path (Join-Path $bak 'compat.cfg'))){
    $cfg = Join-Path $GamePath 'compat.cfg'; $t = Get-Content $cfg -Raw; $orig = $t
    foreach($n in 60,92){
        $t = $t -replace ("(?m)^([ \t]*)/" + "\*if \(compat_AppVidMemory < $n\)([ \t]*\r?\n[ \t]*)return false;\*" + "/"), ('$1if (compat_AppVidMemory < ' + $n + ')$2return false;')
    }
    if($t -ne $orig){ Set-Content $cfg -Value $t -NoNewline -Encoding ASCII; Write-Host "  reversed compat.cfg edits in place" -ForegroundColor Green }
}

# 2. Remove wrapper files (WineD3D / dgVoodoo) from both locations
foreach($dir in @($GamePath,$PROGDATA)){
    foreach($f in $WRAPPER_FILES){ $p = Join-Path $dir $f; if(Test-Path $p){ Remove-Item $p -Force } }
    $legacy = Join-Path $dir '_dgvoodoo_backup'; if(Test-Path $legacy){ Remove-Item $legacy -Recurse -Force }
}
Write-Host "  removed graphics-wrapper files from game folder and ProgramData" -ForegroundColor Green

# 3. Reset registry so the game re-probes cleanly next launch
Remove-Item "$REG_KEY\Test3D" -Recurse -Force -EA SilentlyContinue
if(Test-Path $REG_KEY){ Set-ItemProperty $REG_KEY -Name Is3D -Value 0 -Type DWord -EA SilentlyContinue }
Write-Host "  reset 3D registry state" -ForegroundColor Green

Write-Host "`nUninstalled. The game is back to stock (Steam 'Verify integrity' will also restore it)." -ForegroundColor Green
