# Run against a full-entry fixture linked with startup_gui_stub.c (GUI returns 73)
# and startup_console_parent.c compiled as a console-subsystem executable.
param([Parameter(Mandatory=$true)][string]$Exe,
      [Parameter(Mandatory=$true)][string]$ConsoleParent)
$ErrorActionPreference = 'Stop'
$Exe = [IO.Path]::GetFullPath($Exe)
$ConsoleParent = [IO.Path]::GetFullPath($ConsoleParent)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class StartupLaunch {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct SI {
        public int cb; public string reserved, desktop, title;
        public uint x,y,xSize,ySize,xChars,yChars,fill,flags;
        public short show, reservedSize; public IntPtr reservedPtr,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PI { public IntPtr process,thread; public uint pid,tid; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcess(string app, System.Text.StringBuilder cmd,
        IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd,
        ref SI si, out PI pi);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h,uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h,uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static uint Run(string app,string args,uint flags) {
        SI si = new SI(); si.cb=Marshal.SizeOf(si); si.flags=0x100;
        PI pi;
        var cmd = new System.Text.StringBuilder("\""+app+"\" "+args);
        if (!CreateProcess(app,cmd,IntPtr.Zero,IntPtr.Zero,false,flags,IntPtr.Zero,null,ref si,out pi))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        try {
            if (WaitForSingleObject(pi.process,10000)!=0) {
                TerminateProcess(pi.process,99); throw new Exception("startup timeout");
            }
            uint code;
            if (!GetExitCodeProcess(pi.process,out code)) throw new Exception("exit code unavailable");
            return code;
        } finally { CloseHandle(pi.thread); CloseHandle(pi.process); }
    }
}
'@
function Expect($name, $actual, $expected) {
    if ($actual -ne $expected) { throw "$name expected=$expected actual=$actual" }
    Write-Output "PASS: $name"
}
# Detach the launcher too, so the target's parent has no console (like Explorer).
Expect 'desktop bare selects GUI' ([StartupLaunch]::Run($ConsoleParent,('"'+$Exe+'"'),8)) 73
Expect 'explicit GUI without console' ([StartupLaunch]::Run($Exe,'--gui',8)) 73
Expect 'explicit version without console stays CLI' ([StartupLaunch]::Run($Exe,'version',8)) 0
Expect 'parent console without inherited handles stays CLI' ([StartupLaunch]::Run($ConsoleParent,('"'+$Exe+'"'),16)) 0
foreach ($mode in @('all','stdout','stdin','stderr')) {
    $s = New-Object System.Diagnostics.ProcessStartInfo
    $s.FileName = $Exe
    $s.UseShellExecute = $false
    $s.CreateNoWindow = $true
    $s.RedirectStandardOutput = $mode -in @('all','stdout')
    $s.RedirectStandardInput = $mode -in @('all','stdin')
    $s.RedirectStandardError = $mode -in @('all','stderr')
    $p = [Diagnostics.Process]::Start($s)
    if ($s.RedirectStandardInput) { $p.StandardInput.Close() }
    $out = if ($s.RedirectStandardOutput) { $p.StandardOutput.ReadToEnd() } else { '' }
    $err = if ($s.RedirectStandardError) { $p.StandardError.ReadToEnd() } else { '' }
    if (!$p.WaitForExit(10000)) { $p.Kill(); throw 'timeout' }
    Expect "$mode redirected bare stays CLI" $p.ExitCode 0
    if ($s.RedirectStandardOutput -and $out -notmatch 'usage:') { throw 'missing CLI help' }
    if ($err) { throw "unexpected stderr: $err" }
    $p.Dispose()
}
Write-Output 'PASS: Windows automatic GUI/CLI startup dispatch'
