param([Parameter(Mandatory=$true)][string]$Exe)
$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('cooloo-longpath-' + [guid]::NewGuid().ToString('N'))
$oldRoot = $env:COOLOO_LONG_PATH_ROOT
$oldDriver = $env:SDL_VIDEODRIVER
try {
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $env:COOLOO_LONG_PATH_ROOT = $root + '\'
    $env:SDL_VIDEODRIVER = 'dummy'
    foreach ($length in @(245,285)) {
        $dir = $env:COOLOO_LONG_PATH_ROOT + ('x' * ($length - $env:COOLOO_LONG_PATH_ROOT.Length))
        [IO.Directory]::CreateDirectory('\\?\' + $dir) | Out-Null
        [IO.File]::WriteAllText('\\?\' + $dir + '\existing.txt', 'original')
    }
    & $Exe (Join-Path $PSScriptRoot 'long_paths.lua')
    if ($LASTEXITCODE -ne 0) { throw "Long-path checks failed: $LASTEXITCODE" }
} finally {
    $env:COOLOO_LONG_PATH_ROOT = $oldRoot
    $env:SDL_VIDEODRIVER = $oldDriver
    if ([IO.Directory]::Exists($root)) { [IO.Directory]::Delete('\\?\' + $root, $true) }
}
