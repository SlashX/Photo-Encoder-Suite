# ═══════════════════════════════════════════════════════════════
#  photo_profile_template.ps1 — genereaza UserProfiles\_template.conf
#  cu toate cheile cunoscute + comentarii cu valorile permise.
#
#  Usage:
#    .\photo_profile_template.ps1 [-Force] [-Output <path>]
#  Exit: 0 OK, 1 exists fara -Force, 2 IO error
# ═══════════════════════════════════════════════════════════════
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$Output = ""
)

$ErrorActionPreference = 'Stop'
$ToolsDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptDir  = Split-Path -Parent $ToolsDir

$ProfileLibPath = Join-Path $ScriptDir 'photo_profile_lib.ps1'
if (-not (Test-Path -LiteralPath $ProfileLibPath)) {
    Write-Host "  x photo_profile_lib.ps1 negasit: $ProfileLibPath" -ForegroundColor Red; exit 2
}
. $ProfileLibPath

$UserProfilesDir = Join-Path $ScriptDir 'UserProfiles'
if (-not $Output) { $Output = Join-Path $UserProfilesDir '_template.conf' }

if ((Test-Path -LiteralPath $Output) -and (-not $Force)) {
    Write-Host "  ! exista deja: $Output (foloseste -Force pentru suprascriere)" -ForegroundColor Yellow
    exit 1
}

# Ordine logica — corespunde cu save_profile_conf() din encoder.
$Keys = @(
    'InputDir','OutputDir',
    'Format','Quality','Preset',
    'Resize','ResizeMode','Crop','MaxSize','Depth','HdrMode',
    'UHDR','UHDRGainmapQuality',
    'DJI','DJIBurstGroup','DJILut',
    'DNGPreview','StripExif','SRGB','NoAutoRotate',
    'WatermarkText','WatermarkImage','WatermarkPos','WatermarkOpacity',
    'NoRecursive','Flat','Prefix','Suffix',
    'MinRes','SkipDuplicates','SkipSimilar','SkipSimilarThreshold','LosslessJpeg',
    'ExtractMotion','MotionOnly','MotionShareable','MotionShareableStrict',
    'SkipExisting','Overwrite','Verbose','Compare'
)

function Get-Default([string]$Key) {
    switch ($Key) {
        'Format'              { 'avif' }
        'Quality'             { '80' }
        'ResizeMode'          { 'fit' }
        'WatermarkPos'        { 'southeast' }
        'WatermarkOpacity'    { '30' }
        'SkipSimilarThreshold' { '5' }
        { @('DNGPreview','StripExif','SRGB','NoAutoRotate','NoRecursive','Flat',
            'SkipDuplicates','SkipSimilar','LosslessJpeg','ExtractMotion','MotionOnly',
            'MotionShareable','MotionShareableStrict','SkipExisting','Overwrite',
            'Verbose','Compare') -contains $_ } { 'false' }
        default               { '' }
    }
}

function Get-CommentForSchema([string]$Schema) {
    if (-not $Schema) { return '' }
    $stype = ($Schema -split ':',2)[0]
    $sc    = ($Schema -split ':',2)[1]
    switch ($stype) {
        'enum'     { "permise: $sc" }
        'bool'     { 'true | false' }
        'intrange' {
            $rmin,$rmax = $sc -split ',',2
            "intreg in $rmin..$rmax"
        }
        'int'      { 'intreg' }
        'regex'    { "pattern: $sc" }
        'path'     { 'path catre fisier (lasa gol pentru a sari)' }
        'string'   { 'text liber' }
        default    { '' }
    }
}

$outDir = Split-Path -Parent $Output
if ($outDir -and (-not (Test-Path -LiteralPath $outDir))) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# ═══════════════════════════════════════════════════════════════')
$lines.Add('# Photo Encoder UserProfile — TEMPLATE')
$lines.Add(('# Generat: {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)))
$lines.Add('#')
$lines.Add('# Copiaza/redenumeste acest fisier (ex: my-archive.conf), elimina')
$lines.Add('# # din fata cheilor pe care vrei sa le activezi, si apoi incarca')
$lines.Add('# profilul din meniul interactiv (optiunea 3) sau direct cu')
$lines.Add('#   .\photo_encoder.ps1 -InputDir .\input -OutputDir .\output -Profile my-archive')
$lines.Add('# ═══════════════════════════════════════════════════════════════')
$lines.Add('')

foreach ($key in $Keys) {
    $schema = Get-PhotoProfileSchema $key
    $comment = Get-CommentForSchema $schema
    $default = Get-Default $key
    if ($comment) { $lines.Add("# $key — $comment") }
    $lines.Add("#$key=$default")
    $lines.Add('')
}

Set-Content -LiteralPath $Output -Value $lines -Encoding UTF8

Write-Host "  + $Output" -ForegroundColor Green
Write-Host "  Toate cheile sunt comentate. Decomenteaza ce vrei sa setezi." -ForegroundColor Gray
exit 0
