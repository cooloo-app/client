param([string]$Exe = (Join-Path $PSScriptRoot '..\release\cooloo-windows-x86_64.exe'))
$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WindowProbe {
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
 [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint id);
 [DllImport("kernel32.dll")] public static extern bool FreeConsole();
}
'@
$exe=[IO.Path]::GetFullPath($Exe)
$cfg=Join-Path $env:TEMP ('cooloo-window-'+[guid]::NewGuid().ToString('N'))
foreach ($debug in @($false,$true)) {
 $s=New-Object Diagnostics.ProcessStartInfo
 $s.FileName=$exe
 $s.UseShellExecute=$false
 if ($debug) { $s.Arguments='--debug' }
 $s.EnvironmentVariables['COOLOO_CONFIG']=$cfg
 $s.EnvironmentVariables.Remove('COOLOO_PROBE_STARTUP')
 $s.EnvironmentVariables['COOLOO_HOST']='127.0.0.1:1'
 # Simulate Explorer: no parent console and no redirected handles.
 $s.CreateNoWindow=$true
 $p=[Diagnostics.Process]::Start($s)
 try {
  Start-Sleep -Seconds 2
  $p.Refresh()
  if ($p.HasExited -or $p.MainWindowHandle -eq [IntPtr]::Zero) { throw 'GUI window missing' }
  $small=[WindowProbe]::SendMessage($p.MainWindowHandle,0x7f,[IntPtr]::Zero,[IntPtr]::Zero)
  $large=[WindowProbe]::SendMessage($p.MainWindowHandle,0x7f,[IntPtr]1,[IntPtr]::Zero)
  if ($small -eq [IntPtr]::Zero -or $large -eq [IntPtr]::Zero) { throw 'window icons missing' }
  [WindowProbe]::FreeConsole() | Out-Null
  $attached=[WindowProbe]::AttachConsole([uint32]$p.Id)
  if ($attached) { [WindowProbe]::FreeConsole() | Out-Null }
  if ($attached -ne $debug) { throw "console mismatch: debug=$debug attached=$attached" }
  Write-Output "PASS debug=$debug GUI present; small/large icon set; console=$attached"
 } finally { if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() } }
}
Remove-Item -Recurse -Force $cfg
