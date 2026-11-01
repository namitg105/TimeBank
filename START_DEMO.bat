@echo off
REM =====================================================================
REM  TimeBank -- start everything for the demo, in the right order
REM
REM  Double-click this file. It opens three windows:
REM
REM     1. API        the Spring Boot service -- THE SQL APPEARS HERE
REM     2. APP        the Flutter app, which opens Chrome
REM     3. DATABASE   SQL*Plus, for checking the stored rows
REM
REM  Oracle itself runs as a Windows service and is started first.
REM  Starting services needs Administrator, so if that step is skipped
REM  this file says so rather than failing silently later.
REM
REM  To stop everything: close the three windows. Oracle keeps running,
REM  which is fine -- it is a service.
REM =====================================================================

setlocal
cd /d "%~dp0"

set "MVN=%USERPROFILE%\tools\apache-maven-3.9.9\bin"
set "PATH=%PATH%;%MVN%"
set "JAVA_HOME=C:\Program Files\Java\jdk-26.0.1"
set "ORA=C:\oraclexe\app\oracle\product\11.2.0\server\bin"
set "PATH=%PATH%;%ORA%"

cls
echo.
echo   ==================================================================
echo    TimeBank  --  starting the whole stack
echo   ==================================================================
echo.

REM ---------------------------------------------------------------- 1
echo   [1/4]  Oracle XE ...

net session >nul 2>&1
if errorlevel 1 goto :notadmin

net start OracleServiceXE      >nul 2>&1
net start OracleXETNSListener  >nul 2>&1
echo          services started.
goto :checkdb

:notadmin
echo          (not running as Administrator -- skipping "net start")
echo          If Oracle is already running this is fine.

:checkdb
echo   [2/4]  checking the listener ...
lsnrctl status >nul 2>&1
if errorlevel 1 (
  echo.
  echo          [X] Oracle is not reachable.
  echo.
  echo          Right-click this file, choose "Run as administrator",
  echo          or open an Administrator PowerShell and run:
  echo              net start OracleServiceXE
  echo              net start OracleXETNSListener
  echo.
  pause
  exit /b 1
)
echo          listener is up.

REM ---------------------------------------------------------------- 2
echo   [3/4]  starting the API on port 8081 ...

REM Free the port in case an API from an earlier run is still holding it.
powershell -NoProfile -Command ^
  "Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }" >nul 2>&1

start "TimeBank API  --  THE SQL APPEARS IN THIS WINDOW" cmd /k ^
  "cd /d "%~dp0api" && set PATH=%PATH% && set JAVA_HOME=%JAVA_HOME% && mvn spring-boot:run"

echo          waiting for it to boot ...
timeout /t 35 /nobreak >nul

REM ---------------------------------------------------------------- 3
echo   [4/4]  starting the Flutter app and a database window ...

start "TimeBank DATABASE  --  run @sql\check.sql here" cmd /k ^
  "cd /d "%~dp0sql" && sqlplus timebank/timebank@localhost:1521/XE"

start "TimeBank APP  --  Flutter" cmd /k ^
  "cd /d "%~dp0timebank" && flutter run -d chrome"

echo.
echo   ==================================================================
echo    All three windows are starting.
echo   ==================================================================
echo.
echo    API        Spring Boot on 8081.  WATCH THIS ONE -- every click
echo               in the app prints the SQL it ran, with bind values,
echo               row counts and timings.
echo.
echo    APP        Chrome opens by itself after a minute or so.
echo.
echo    DATABASE   SQL*Plus, already connected. Type:
echo                   @check.sql
echo               before and after an action to see the rows change.
echo.
echo    Quick check in a browser:  localhost:8081/api/students
echo.
echo   ------------------------------------------------------------------
echo    If the app shows connection errors, the API window is the one
echo    to look at -- it will say what went wrong.
echo   ------------------------------------------------------------------
echo.
pause
