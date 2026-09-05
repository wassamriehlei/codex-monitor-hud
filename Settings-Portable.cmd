@echo off
powershell.exe -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0scripts\start-portable.ps1" -Settings %*
