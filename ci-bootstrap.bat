@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" x64 > "D:\weasel-build\weasel\deps\boost_1_84_0\vcvars.log" 2>&1
if errorlevel 1 (echo VCVARS_FAILED & exit /b 21)
cd /d "D:\weasel-build\weasel\deps\boost_1_84_0"
call bootstrap.bat vc143 > bootstrap.log 2>&1
if not exist b2.exe exit /b 22
exit /b 0
