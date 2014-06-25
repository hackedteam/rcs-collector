@echo off

set CWD=%CD%
cd /D C:\RCS\Collector

ruby bin\rcs-collector-diagnostic %*

cd /D %CWD%
