@echo off

set CWD=%CD%
cd /D C:\RCS\DB

ruby bin\rcs-collector-log %*

cd /D %CWD%
