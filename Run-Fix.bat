@echo off
REM Double-click launcher for the Bejeweled Twist compatibility fix.
REM Uses -ExecutionPolicy Bypass so the unsigned script runs without changing
REM your system's PowerShell policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-BejeweledTwistFix.ps1" %*
echo.
pause
