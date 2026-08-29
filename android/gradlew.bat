@ECHO OFF
SETLOCAL ENABLEEXTENSIONS
SET "APP_HOME=%~dp0"
SET "PROPERTIES=%APP_HOME%gradle\wrapper\gradle-wrapper.properties"

FOR /F "tokens=2 delims==" %%A IN ('findstr /B "distributionUrl=" "%PROPERTIES%"') DO SET "DIST_URL=%%A"
FOR /F "tokens=2 delims==" %%A IN ('findstr /B "distributionSha256Sum=" "%PROPERTIES%"') DO SET "DIST_SHA=%%A"
SET "DIST_URL=%DIST_URL:\:=:%"
FOR %%A IN ("%DIST_URL%") DO SET "ZIP_NAME=%%~nxA"
SET "GRADLE_VERSION=%ZIP_NAME:gradle-=%"
SET "GRADLE_VERSION=%GRADLE_VERSION:-bin.zip=%"
SET "GRADLE_USER_HOME=%GRADLE_USER_HOME%"
IF "%GRADLE_USER_HOME%"=="" SET "GRADLE_USER_HOME=%USERPROFILE%\.gradle"
SET "DIST_DIR=%GRADLE_USER_HOME%\wrapper\dists\gradle-%GRADLE_VERSION%-bin"
SET "DIST_ZIP=%DIST_DIR%\%ZIP_NAME%"
SET "DIST_HOME=%DIST_DIR%\gradle-%GRADLE_VERSION%"

IF NOT EXIST "%DIST_HOME%\bin\gradle.bat" (
  IF NOT EXIST "%DIST_ZIP%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%DIST_URL%' -OutFile '%DIST_ZIP%'"
    IF ERRORLEVEL 1 EXIT /B 1
  )
  FOR /F "tokens=*" %%A IN ('powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '%DIST_ZIP%').Hash.ToLower()"') DO SET "ACTUAL_SHA=%%A"
  IF /I NOT "%ACTUAL_SHA%"=="%DIST_SHA%" (
    ECHO ERROR: Gradle distribution checksum mismatch.
    DEL /Q "%DIST_ZIP%" >NUL 2>&1
    EXIT /B 1
  )
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force '%DIST_ZIP%' '%DIST_DIR%'"
  IF ERRORLEVEL 1 EXIT /B 1
)

CALL "%DIST_HOME%\bin\gradle.bat" %*
ENDLOCAL
