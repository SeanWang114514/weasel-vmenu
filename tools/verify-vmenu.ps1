Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class VM{[DllImport("user32.dll")]public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);[DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte sc,uint f,UIntPtr e);[DllImport("user32.dll")]public static extern uint MapVirtualKey(uint c,uint t);[DllImport("user32.dll")]public static extern bool EnumWindows(EnumProc cb,IntPtr l);[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);[DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,System.Text.StringBuilder s,int n);[DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);[DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RECT r);public struct RECT{public int L,T,R,B;}public delegate bool EnumProc(IntPtr h,IntPtr l);public static string Dump(uint want){var sb=new System.Text.StringBuilder();EnumWindows((h,l)=>{uint pid;GetWindowThreadProcessId(h,out pid);if(pid==want&&IsWindowVisible(h)){var cn=new System.Text.StringBuilder(64);GetClassName(h,cn,64);if(cn.ToString().StartsWith("ATL")){RECT r;GetWindowRect(h,out r);sb.Append(string.Format("{0},{1}-{2},{3} ",r.L,r.T,r.R,r.B));}}return true;},IntPtr.Zero);return sb.ToString();}}'
function Tap([byte]$vk){ $sc=[VM]::MapVirtualKey([uint32]$vk,0); [VM]::keybd_event($vk,[byte]$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [VM]::keybd_event($vk,[byte]$sc,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 130 }
function Shot([string]$p){ $bmp=New-Object Drawing.Bitmap 1040,460; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen(60,40,0,0,(New-Object Drawing.Size(1040,460))); $bmp.Save($p,[Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }
Get-Process notepad -EA SilentlyContinue | Stop-Process -Force; Start-Sleep -Milliseconds 900
Start-Process notepad; Start-Sleep -Seconds 3
$np=Get-Process notepad | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$id=[uint32]$np.Id
[void][VM]::MoveWindow($np.MainWindowHandle,60,40,1040,460,$true); [VM]::SetForegroundWindow($np.MainWindowHandle); Start-Sleep -Milliseconds 400
$t='D:\VibeCoding\输入法\repo\weasel-vmenu\tools\type-and-shot.ps1'
for($i=1;$i -le 4;$i++){
  & $t -Target notepad -Keys 's,h,i' -Out 'D:\weasel-build\shots\_t.png' -NoClick *> $null; Start-Sleep -Milliseconds 600
  if([VM]::Dump($id)){ "✅ 中文态（第 $i 次）"; break }
  Tap 0x1B; Start-Sleep -Milliseconds 250; Tap 0x10; Start-Sleep -Milliseconds 350 }
Tap 0x1B; Start-Sleep -Milliseconds 400

"--- 1) 按 v 打开主菜单 ---"
Tap 0x56; Start-Sleep -Milliseconds 900
"  候选窗: 「$([VM]::Dump($id))」"
Shot 'D:\weasel-build\shots\g1_vmenu_new.png'

"--- 2) 按 3（应为 快捷输入）---"
Tap 0x33; Start-Sleep -Milliseconds 900
"  候选窗: 「$([VM]::Dump($id))」"
Shot 'D:\weasel-build\shots\g2_v3_quick.png'
"--- 2b) 子菜单里按 1（应为计算 cC）---"
Tap 0x31; Start-Sleep -Milliseconds 900
"  候选窗: 「$([VM]::Dump($id))」"
Shot 'D:\weasel-build\shots\g3_quick_calc.png'
Tap 0x1B; Start-Sleep -Milliseconds 400

"--- 3) 按 v 再按 5（应为 常用语）---"
Tap 0x56; Start-Sleep -Milliseconds 800
Tap 0x35; Start-Sleep -Milliseconds 900
"  候选窗: 「$([VM]::Dump($id))」"
Shot 'D:\weasel-build\shots\g4_v5_fav.png'
"--- 3b) 常用语里按 1（应上屏收藏词）---"
Tap 0x31; Start-Sleep -Milliseconds 900
[VM]::keybd_event(0x11,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80
Tap 0x41; Tap 0x43; [VM]::keybd_event(0x11,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 400
"  上屏内容 = 「$(Get-Clipboard -Raw)」"
Get-ChildItem 'D:\weasel-build\shots\g*.png' | ForEach-Object { "  $($_.Name) $($_.Length) B" }
