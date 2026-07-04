<#
    Apply-BejeweledTwistFix.ps1
    ---------------------------------------------------------------------------
    Makes Bejeweled Twist (Steam, v1.0.3.7482) run on modern Windows with 3D
    acceleration, selectable High/Ultra resolution, and working mouse AND touch
    input. Redistributes NO original game binaries - only patch instructions.

    What it does (all reversible; originals backed up to <game>\_original_backup):
      1. Verifies the installed BejeweledTwist.exe is the known version.
      2. Applies a 1-byte binary patch (video-card check bypass).
      3. Comments out the VRAM gates in compat.cfg (unlocks High/Ultra res).
      4. Downloads WineD3D from its OFFICIAL source (fdossena.com) and installs
         its DirectDraw/D3D->OpenGL wrapper DLLs (fixes the startup crash; unlike
         dgVoodoo it does not hijack the cursor, so touch input works).
      5. Clears any stale 3D-probe verdict and enables 3D by default.

    USAGE:
      powershell -ExecutionPolicy Bypass -File .\Apply-BejeweledTwistFix.ps1
      (optionally  -GamePath "D:\SteamLibrary\steamapps\common\Bejeweled Twist")
#>
[CmdletBinding()]
param([string]$GamePath, [switch]$Force)

$ErrorActionPreference = 'Stop'

$EXE_NAME     = 'BejeweledTwist.exe'
$STOCK_SHA    = '45A325F4D08B7F60DDB5054171C8A024AC3FFFFD0EFE5150F9C5ABD2225FAAFD'
$PATCHED_SHA  = '27D5524D122FC2C447F7519A247C8A0B2EBA44790865A55691D27D23949379CF'
$VCARD_OFFSET = 0x1D91DB
$VCARD_FROM   = 0x75
$VCARD_TO     = 0xEB
$WINED3D_URL  = 'https://downloads.fdossena.com/geth.php?r=wined3dst-latest'
$WINED3D_DLLS = @('ddraw.dll','d3d9.dll','d3d8.dll','wined3d.dll')
$DGV_LEFTOVERS= @('dgVoodoo.conf','D3DImm.dll')   # remove if a previous dgVoodoo-based fix is present
$PROGDATA     = Join-Path $env:ProgramData 'PopCap Games\BejeweledTwist'
$REG_KEY      = 'HKCU:\Software\Steam\BejeweledTwist'

function Write-Step($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok  ($m){ Write-Host "    [ok] $m"  -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!!] $m" -ForegroundColor Yellow }

function Find-GamePath([string]$Explicit){
    if($Explicit){ return $Explicit }
    $c=@()
    try {
        $steam=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -EA Stop).SteamPath -replace '/','\'
        $vdf=Join-Path $steam 'steamapps\libraryfolders.vdf'
        if(Test-Path $vdf){ foreach($l in Get-Content $vdf){ if($l -match '"path"\s*"(.+?)"'){ $c += ($matches[1] -replace '\\\\','\') } } }
        $c += $steam
    } catch {}
    $c += 'C:\Games\Steam','C:\Program Files (x86)\Steam'
    foreach($lib in ($c|Select-Object -Unique)){ $p=Join-Path $lib 'steamapps\common\Bejeweled Twist'; if(Test-Path (Join-Path $p $EXE_NAME)){ return $p } }
    return $null
}

# ---- locate + verify -------------------------------------------------------
$GamePath = Find-GamePath $GamePath
if(-not $GamePath -or -not (Test-Path (Join-Path $GamePath $EXE_NAME))){
    throw "Could not find $EXE_NAME. Install via Steam, then re-run with -GamePath '<Bejeweled Twist folder>'."
}
$exe = Join-Path $GamePath $EXE_NAME
$cfg = Join-Path $GamePath 'compat.cfg'
Write-Step "Game found: $GamePath"

$sha = (Get-FileHash $exe -Algorithm SHA256).Hash
switch($sha){
    $STOCK_SHA   { Write-Ok 'Stock v1.0.3.7482 detected.' }
    $PATCHED_SHA { Write-Ok 'Executable already patched.' }
    default {
        if($Force){ Write-Warn2 "Unrecognized exe hash ($sha). Proceeding due to -Force; offsets may not match!" }
        else { throw "Unrecognized $EXE_NAME (SHA256 $sha). Targets v1.0.3.7482. Re-run with -Force to override." }
    }
}

# ---- backup ----------------------------------------------------------------
$bak = Join-Path $GamePath '_original_backup'
New-Item -ItemType Directory -Force $bak | Out-Null
foreach($f in @($EXE_NAME,'compat.cfg')){ $d=Join-Path $bak $f; if(-not (Test-Path $d) -and (Test-Path (Join-Path $GamePath $f))){ Copy-Item (Join-Path $GamePath $f) $d } }
Write-Ok "Originals backed up to $bak"

# ---- 1. patch exe ----------------------------------------------------------
Write-Step 'Patching executable (video-card check bypass)'
$bytes=[IO.File]::ReadAllBytes($exe)
if($bytes[$VCARD_OFFSET] -eq $VCARD_TO){ Write-Ok 'Byte already patched.' }
elseif($bytes[$VCARD_OFFSET] -eq $VCARD_FROM){ $bytes[$VCARD_OFFSET]=$VCARD_TO; [IO.File]::WriteAllBytes($exe,$bytes); Write-Ok ("Patched offset 0x{0:X}: 0x{1:X2}->0x{2:X2}" -f $VCARD_OFFSET,$VCARD_FROM,$VCARD_TO) }
elseif(-not $Force){ throw ("Unexpected byte 0x{0:X2} at 0x{1:X}; aborting." -f $bytes[$VCARD_OFFSET],$VCARD_OFFSET) }

# ---- 2. patch compat.cfg ---------------------------------------------------
Write-Step 'Patching compat.cfg (unlock High/Ultra resolutions)'
$t=Get-Content -LiteralPath $cfg -Raw; $before=$t
foreach($n in 60,92){ if($t -notmatch "/\*if \(compat_AppVidMemory < $n\)"){ $t=$t -replace "(?m)^([ \t]*)if \(compat_AppVidMemory < $n\)([ \t]*\r?\n[ \t]*)return false;",('$1/*if (compat_AppVidMemory < '+$n+')$2return false;*/') } }
if($t -ne $before){ Set-Content -LiteralPath $cfg -Value $t -NoNewline -Encoding ASCII; Write-Ok 'VRAM gates commented out.' } else { Write-Ok 'compat.cfg already patched.' }

# ---- 3. install WineD3D -----------------------------------------------------
Write-Step 'Installing WineD3D wrapper (from official source: fdossena.com)'
$tmp=Join-Path $env:TEMP ('wd3d_'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $tmp|Out-Null
try {
    $zip=Join-Path $tmp 'wined3d.zip'
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $WINED3D_URL -OutFile $zip -UseBasicParsing -MaximumRedirection 5
    Expand-Archive $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force $PROGDATA | Out-Null
    foreach($loc in @($GamePath,$PROGDATA)){
        # clean any previous dgVoodoo-based install so the two wrappers don't collide
        foreach($f in $DGV_LEFTOVERS){ $p=Join-Path $loc $f; if(Test-Path $p){ Remove-Item $p -Force } }
        foreach($d in $WINED3D_DLLS){
            $found=Get-ChildItem -Recurse -LiteralPath $tmp -Filter $d -File | Select-Object -First 1
            if(-not $found){ throw "WineD3D package is missing $d (layout changed?)" }
            Copy-Item $found.FullName (Join-Path $loc $d) -Force
        }
    }
    Write-Ok "Installed $($WINED3D_DLLS -join ', ') into game folder and ProgramData."
}
catch { Write-Warn2 "WineD3D download/install failed: $($_.Exception.Message)"; Write-Warn2 'Without it the game crashes on launch. Re-run when online.' }
finally { Remove-Item -Recurse -Force $tmp -EA SilentlyContinue }

# ---- 4. registry -----------------------------------------------------------
Write-Step 'Resetting 3D state in registry'
Remove-Item "$REG_KEY\Test3D" -Recurse -Force -EA SilentlyContinue
New-Item -Path $REG_KEY -Force | Out-Null
New-ItemProperty -Path $REG_KEY -Name 'Is3D'           -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $REG_KEY -Name 'HighResolution' -Value 1 -PropertyType DWord -Force | Out-Null
Write-Ok 'Stale probe cleared; 3D + high-res enabled (adjust later in-game via Options).'

Write-Host "`nDone. Launch Bejeweled Twist from Steam." -ForegroundColor Green
Write-Host "If Steam 'Verify integrity of game files' runs, it reverts the exe/compat.cfg/DLLs - just run this script again." -ForegroundColor DarkGray
