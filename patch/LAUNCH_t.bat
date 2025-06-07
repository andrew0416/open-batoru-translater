@echo off
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