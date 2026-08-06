@echo off
setlocal
set "PATCH_DIR=%~dp0"

rem Always resolve the updater, Java runtime, and config from the patch folder.
pushd "%PATCH_DIR%"

if exist "%PATCH_DIR%translate-updater.exe" (
  "%PATCH_DIR%translate-updater.exe"
) else (
  echo [translate-db] translate-updater.exe was not found. Starting the game without an update check.
)

"./jdk/bin/java" ^
-javaagent:"agent.jar" ^
-Dprism.forceGPU=true ^
-Dprism.dirtyopts=false ^
--module-path "./jdk/jfx/lib" ^
--add-modules javafx.swing,javafx.web,java.compiler,java.desktop ^
-Dfile.encoding=UTF-8 ^
-Dsun.stdout.encoding=UTF-8 ^
-Dsun.stderr.encoding=UTF-8 ^
-jar OpenBatoru.jar

popd
endlocal
