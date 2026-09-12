@echo off
chcp 65001 >nul
rem Open the visual settings window for the Weasel v-menu feature.
rem The window process is normally already resident (kept alive by
rem vmenu-watcher.ps1), so this only asks it to show itself and appears instantly.
rem ASCII-only source on purpose: cmd.exe decodes a .bat with the active code
rem page and desyncs on multi-byte characters split across read buffers.
set "RIME_DIR=D:\rime-sandbox"
rem Ask the resident window to show itself...
>"%RIME_DIR%\open-settings.flag" echo open
rem ...and if nothing was running, start the supervisor that brings it up.
start "Rime V-Menu Watcher" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0vmenu-watcher.ps1" -RimeDir "%RIME_DIR%" >nul 2>&1
