@echo off
chcp 65001 >nul
rem Start the two background helpers the v-menu feature needs.
rem
rem   1) clipboard-sync.ps1  - mirrors the Windows clipboard into
rem      <RimeDir>\clipboard-cache.txt (one entry per line, newest first,
rem      de-duplicated, capped). Runs outside the IME on purpose: reading the
rem      clipboard from inside the Rime input thread used to freeze typing.
rem   2) vmenu-watcher.ps1   - keeps ONE resident settings window alive.
rem      vmenu-settings-gui.ps1 builds its window hidden and watches
rem      <RimeDir>\open-settings.flag, which the IME writes when you press  v
rem      then  1 ; the window then appears in about 0.1 s. The IME never spawns
rem      a process itself (spawning from the Rime input thread used to freeze
rem      typing).
rem
rem Older instances of both are stopped first, so only one of each keeps running.
rem Kept ASCII-only on purpose: cmd.exe decodes a .bat with the active code page
rem and desyncs on multi-byte characters split across read buffers.
set "RIME_DIR=D:\rime-sandbox"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0clipboard-sync-stop.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0vmenu-watcher-stop.ps1"

start "Rime Clipboard Sync" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0clipboard-sync.ps1" -RimeDir "%RIME_DIR%" -Max 50 -IntervalMs 1000 >nul 2>&1
start "Rime V-Menu Watcher" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0vmenu-watcher.ps1" -RimeDir "%RIME_DIR%" >nul 2>&1

rem Also open the settings window: the watcher starts it with -ShowNow because
rem this flag file exists, or the already resident window shows itself.
>"%RIME_DIR%\open-settings.flag" echo open

echo Clipboard sync and v-menu watcher started, settings window opening.
echo   press  v  then  1  in the input method to open the settings window,
echo   or double-click the launcher .bat in this folder to open it directly.
