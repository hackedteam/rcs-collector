@echo off

set CWD=%CD%
cd /D C:\RCS\Collector

ruby bin\rcs-carrier-stats %*

cd /D %CWD%
