Add-Type @'
using System;
using System.Runtime.InteropServices;
public class HKH {
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int s);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public KEYBDINPUT ki; }
  public static void Down() { var d=new INPUT[1]; d[0].type=1; d[0].ki.wVk=0x7B; SendInput(1,d,Marshal.SizeOf(typeof(INPUT))); }
  public static void Up() { var u=new INPUT[1]; u[0].type=1; u[0].ki.wVk=0x7B; u[0].ki.dwFlags=2; SendInput(1,u,Marshal.SizeOf(typeof(INPUT))); }
  public static short State() { return GetAsyncKeyState(0x7B); }
}
'@
[HKH]::Down()
Write-Output ("after down: " + [HKH]::State())
Start-Sleep -Milliseconds 800
Write-Output ("before up: " + [HKH]::State())
[HKH]::Up()
Write-Output "released"
