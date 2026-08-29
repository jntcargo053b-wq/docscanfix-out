@echo off
setlocal
set "APP_HOME=%~dp0"
set "WRAPPER_JAR=%APP_HOME%gradle\wrapper\gradle-wrapper.jar"
set "WRAPPER_URL=https://raw.githubusercontent.com/gradle/gradle/v8.13.0/gradle/wrapper/gradle-wrapper.jar"
set "WRAPPER_SHA256=81a82aaea5abcc8ff68b3dfcb58b3c3c429378efd98e7433460610fecd7ae45f"

if not exist "%WRAPPER_JAR%" (
  if not exist "%APP_HOME%gradle\wrapper" mkdir "%APP_HOME%gradle\wrapper"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -UseBasicParsing -Uri '%WRAPPER_URL%' -OutFile '%WRAPPER_JAR%.part'; $actual=(Get-FileHash -Algorithm SHA256 '%WRAPPER_JAR%.part').Hash.ToLowerInvariant(); if ($actual -ne '%WRAPPER_SHA256%') { Remove-Item -Force '%WRAPPER_JAR%.part'; throw 'Gradle Wrapper JAR checksum mismatch' }; Move-Item -Force '%WRAPPER_JAR%.part' '%WRAPPER_JAR%'"
  if errorlevel 1 exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$actual=(Get-FileHash -Algorithm SHA256 '%WRAPPER_JAR%').Hash.ToLowerInvariant(); if ($actual -ne '%WRAPPER_SHA256%') { throw 'Gradle Wrapper JAR checksum mismatch' }"
if errorlevel 1 exit /b 1

java -classpath "%WRAPPER_JAR%" org.gradle.wrapper.GradleWrapperMain %*
exit /b %ERRORLEVEL%
