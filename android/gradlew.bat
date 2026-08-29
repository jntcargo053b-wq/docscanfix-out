@echo off
rem Flutter invokes this script on Windows Android builds.
rem Gradle is provisioned by GitHub Actions via setup-gradle (8.13).
where gradle >nul 2>&1
if errorlevel 1 (
  echo ERROR: Gradle is not available on PATH.
  echo Run gradle/actions/setup-gradle with gradle-version: 8.13 first.
  exit /b 127
)
gradle %*
