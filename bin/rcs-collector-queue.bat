@echo off

set CWD=%CD%
cd /D C:\RCS\Collector

ruby bin\rcs-collector-queue %*

cd /D %CWD%
