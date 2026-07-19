@echo off
REM Minecraft Mod Sync & Launch — Windows
REM Pulls the latest mods and resourcepacks from the shared repo, then launches Minecraft.

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "REPO_DIR=%SCRIPT_DIR%.."
set "MC_DIR=%APPDATA%\.minecraft"

if not exist "%MC_DIR%" (
    echo Error: Minecraft directory not found at %MC_DIR%
    echo Make sure Minecraft is installed and has been run at least once.
    pause
    exit /b 1
)

REM Without Git LFS, git pull downloads placeholder text files instead of real jars.
git lfs version >nul 2>&1
if errorlevel 1 (
    echo Error: Git LFS is not installed.
    echo Install it from https://git-lfs.com/ then run: git lfs install
    pause
    exit /b 1
)

echo === Minecraft Mod Sync ===
echo.

REM Pull latest changes
echo Pulling latest mods and resourcepacks...
cd /d "%REPO_DIR%"
git pull --ff-only origin main
if errorlevel 1 (
    echo.
    echo Error: Git pull failed. You may have local changes.
    echo Run "git status" in the repo to check.
    pause
    exit /b 1
)
git lfs pull
echo.

REM Sync mods (common = both sides, client = client-only). Server-only mods live
REM in mods\server\ and are intentionally not installed on players' machines.
echo Syncing mods...
del /q "%MC_DIR%\mods\*.jar" 2>nul
copy /y "%REPO_DIR%\mods\common\*.jar" "%MC_DIR%\mods\" >nul
copy /y "%REPO_DIR%\mods\client\*.jar" "%MC_DIR%\mods\" >nul
echo   Mods synced.

REM Sync resourcepacks
echo Syncing resourcepacks...
del /q "%MC_DIR%\resourcepacks\*.zip" 2>nul
if exist "%REPO_DIR%\resourcepacks\*.zip" (
    copy /y "%REPO_DIR%\resourcepacks\*.zip" "%MC_DIR%\resourcepacks\" >nul
    echo   Resourcepacks synced.
) else (
    echo   No resourcepacks to sync.
)

echo.
echo Sync complete! Launching Minecraft...

REM Launch Minecraft
start "" "%ProgramFiles(x86)%\Minecraft Launcher\MinecraftLauncher.exe" 2>nul || (
    start "" "%ProgramFiles%\Minecraft Launcher\MinecraftLauncher.exe" 2>nul || (
        echo Could not find Minecraft Launcher. Please launch it manually.
    )
)

pause
