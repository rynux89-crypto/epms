@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Tomcat 9.0\webapps\ROOT\scripts\run_aggregate_measurements.ps1" -Mode hourly -Server "localhost,1433" -Database "epms" -User "sa" -Password "1234"
