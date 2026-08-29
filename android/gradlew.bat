@echo off
rem Flutter invokes this script on Windows Android builds.
rem GitHub Actions provisions the exact Gradle 8.13 distribution.
rem No Gradle Wrapper JAR is used by this project.
where gradle >nul 2>&1
if errorlevel 1 (
  echo ERROR: Gradle is not available on PATH.
  echo Run gradle/actions/setup-gradle with gradle-version: 8.13 first.
  exit /b 127
)
gradle %*
