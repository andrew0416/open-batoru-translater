@echo off
setlocal
cd /d "%~dp0"

dotnet publish TranslateDbUpdater.csproj ^
  -c Release ^
  -r win-x64 ^
  --self-contained true ^
  -p:PublishSingleFile=true ^
  -p:PublishTrimmed=false

if errorlevel 1 exit /b %errorlevel%

copy /y ".\bin\Release\net8.0\win-x64\publish\translate-updater.exe" "..\..\patch\translate-updater.exe"
