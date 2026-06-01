@echo off
setlocal
cd /d "%~dp0"
python ups_modbus_simulator.py --host 127.0.0.1 --port 1502 --control-host 127.0.0.1 --control-port 1503 --scenario normal --open-browser
