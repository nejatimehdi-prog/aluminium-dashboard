@echo off
rem Local Iran collector for Windows Task Scheduler. Output goes to collect_iran.log.
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
if exist ".venv\Scripts\python.exe" (
  ".venv\Scripts\python.exe" collect_iran.py >> collect_iran.log 2>&1
) else (
  py -3.12 collect_iran.py >> collect_iran.log 2>&1
)
