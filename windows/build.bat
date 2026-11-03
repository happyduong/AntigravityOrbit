@echo off
setlocal
echo === Building Antigravity Orbit for Windows 11 (WinUI 3) ===

set PROJECT_DIR=%~dp0AntigravityOrbit
set DIST_DIR=%~dp0dist

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

echo 1. Restoring NuGet dependencies...
dotnet restore "%PROJECT_DIR%\AntigravityOrbit.csproj"
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

echo 2. Publishing self-contained executable (win-x64)...
dotnet publish "%PROJECT_DIR%\AntigravityOrbit.csproj" -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:WindowsPackageType=None -o "%DIST_DIR%"
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

echo.
echo ✔ Build successful! Output located in %DIST_DIR%
endlocal

