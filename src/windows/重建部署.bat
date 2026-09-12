@echo off
chcp 65001 >nul
title Weasel v-menu - rebuild and restart
rem ===================================================================
rem On this machine WeaselDeployer / "WeaselServer /deploy" never recompile
rem a schema: librime's DetectModifications gate decides "nothing changed"
rem and aborts the whole deployment run. So after editing
rem rime_ice.custom.yaml, run this file instead:
rem   1) write the custom.yaml semantics back into build\rime_ice.schema.yaml
rem      (including restoring the v2/v3 symbol tables)
rem   2) restart WeaselServer so the new compiled schema and lua files load
rem This script is idempotent and safe to run repeatedly.
rem Kept ASCII-only on purpose: cmd.exe decodes a .bat with the active code
rem page and desyncs on multi-byte characters split across read buffers.
rem ===================================================================
set "RIME_DIR=D:\rime-sandbox"

echo [1/2] syncing rime_ice.custom.yaml into the compiled schema ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch-build-schema.ps1" -RimeDir "%RIME_DIR%"
if errorlevel 1 (
  echo.
  echo [ERROR] patch failed, see the output above.
  pause
  exit /b 1
)

echo.
echo [2/2] restarting the Weasel service ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process WeaselServer -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep -Seconds 1; Start-Process 'C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe'; Start-Sleep -Seconds 3; if (Get-Process WeaselServer -ErrorAction SilentlyContinue) { 'WeaselServer started' } else { 'WeaselServer FAILED to start' }"

echo.
echo Done. Switch to Weasel and type v to open the feature menu.
pause
