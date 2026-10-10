# Optional COOLOO_TEST_HOST points to an isolated loopback coolood (never production).
param([string]$Exe = (Join-Path $PSScriptRoot '..\release\cooloo-windows-x86_64.exe'))
$ErrorActionPreference = 'Stop'
$exe = [IO.Path]::GetFullPath($Exe)
$cfg = Join-Path $env:TEMP ('cooloo-ui-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $cfg | Out-Null
function Run-Test($arguments, $inputText = '') {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = $arguments
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.EnvironmentVariables['COOLOO_CONFIG'] = $cfg
    $start.EnvironmentVariables['COOLOO_PROBE_STARTUP'] = '1'
    if ($env:COOLOO_TEST_HOST) { $start.EnvironmentVariables['COOLOO_HOST'] = $env:COOLOO_TEST_HOST }
    if ($inputText) {
        # .NET Framework's Process.StandardInput injects a UTF-8 BOM. Use a
        # BOM-free file through CMD to exercise real Windows stdin redirection.
        $infile = Join-Path $cfg 'stdin.txt'
        $outfile = Join-Path $cfg 'stdout.txt'
        $errfile = Join-Path $cfg 'stderr.txt'
        [IO.File]::WriteAllText($infile, $inputText, [Text.Encoding]::ASCII)
        $start.FileName = $env:ComSpec
        $redirection = '< "' + $infile + '"'
        if ($arguments -eq 'send general') { $redirection = 'type "' + $infile + '" |' }
        if ($arguments -eq 'send general') {
            $start.Arguments = '/d /s /c "' + $redirection + ' "' + $exe + '" ' + $arguments + ' > "' + $outfile + '" 2> "' + $errfile + '""'
        } else {
            $start.Arguments = '/d /s /c ""' + $exe + '" ' + $arguments + ' ' + $redirection + ' > "' + $outfile + '" 2> "' + $errfile + '""'
        }
        $start.RedirectStandardInput = $false
        $start.RedirectStandardOutput = $false
        $start.RedirectStandardError = $false
        $p = [System.Diagnostics.Process]::Start($start)
        if (-not $p.WaitForExit(15000)) { $p.Kill(); throw 'timeout' }
        $out = [IO.File]::ReadAllText($outfile)
        $err = [IO.File]::ReadAllText($errfile)
    } else {
        $p = [System.Diagnostics.Process]::Start($start)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        if (-not $p.WaitForExit(15000)) { $p.Kill(); throw 'timeout' }
    }
    Write-Host "ARGS=$arguments EXIT=$($p.ExitCode)"
    Write-Host "STDOUT=$out"
    Write-Host "STDERR=$err"
    return @{Code=$p.ExitCode; Out=$out; Err=$err}
}
$r = Run-Test '--help'
if ($r.Code -ne 0 -or $r.Out -notmatch 'usage:') { throw 'help/redirection failed' }
$r = Run-Test 'bogus'
if ($r.Code -ne 2 -or $r.Err -notmatch 'unknown command') { throw 'stderr/exit failed' }
$r = Run-Test 'keygen'
if ($r.Code -ne 0 -or $r.Out -notmatch 'fingerprint:') { throw 'keygen failed' }
$r = Run-Test '--debug'
if ($r.Code -ne 0 -or $r.Err -notmatch 'first frame') { throw 'debug GUI failed' }
$r = Run-Test ''
if ($r.Code -ne 0 -or $r.Err -notmatch 'first frame') { throw 'bare GUI failed' }
$r = Run-Test '--lua-dev'
if ($r.Code -ne 2 -or $r.Err -notmatch 'requires a directory') { throw 'argument error failed' }
if ($env:COOLOO_TEST_HOST) {
    $r = Run-Test 'rooms' "y`n"
    if ($r.Code -ne 0 -or $r.Err -notmatch 'trust and pin') { throw 'piped TOFU input failed' }
    $r = Run-Test 'whoami --register ui-test'
    if ($r.Code -ne 0 -or $r.Out -notmatch 'NICK ui-test') { throw 'register failed' }
    $r = Run-Test 'send general' "transparent C pipe test`nsecond line`n"
    if ($r.Code -ne 0 -or $r.Out -notmatch '^OK ') { throw 'piped send failed' }
    $r = Run-Test 'read general -1'
    if ($r.Code -ne 0 -or $r.Out -notmatch 'transparent C pipe test' -or $r.Out -notmatch 'second line') { throw 'readback failed' }
    Write-Output 'PASS: Windows piped TOFU, registration, multiline stdin send and readback'
}
Remove-Item -Recurse -Force $cfg
Write-Output 'PASS: Windows help, stderr, exit code, keygen, debug GUI and bare GUI'
