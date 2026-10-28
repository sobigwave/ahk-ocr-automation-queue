@echo off
setlocal
set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey.exe"
if not exist "%AHK%" set "AHK=%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey.exe"
if not exist "%AHK%" (
    echo [ERROR] AutoHotkey v2 was not found.
    echo Install AutoHotkey v2 from https://www.autohotkey.com/
    pause
    exit /b 1
)
for %%F in ("%~dp0*.ahk") do (
    start "" "%AHK%" "%%~fF"
    exit /b 0
)
echo [ERROR] No .ahk file found in this folder.
pause
exit /b 1
