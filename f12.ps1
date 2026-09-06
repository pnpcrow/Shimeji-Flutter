Add-Type @'
using System;
using System.Runtime.InteropServices;
public class HK2 {
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int s);
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public KEYBDINPUT ki; }
  public static void Tap(ushort vk) {
    var d=new INPUT[1]; d[0].type=1; d[0].ki.wVk=vk; SendInput(1,d,Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(80);
    var u=new INPUT[1]; u[0].type=1; u[0].ki.wVk=vk; u[0].ki.dwFlags=2; SendInput(1,u,Marshal.SizeOf(typeof(INPUT)));
  }
}
'@
[HK2]::Tap(0x7B)
Write-Output "F12 sent"
