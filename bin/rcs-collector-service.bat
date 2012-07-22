@echo off

IF %1 == restart (
  net stop RCSCollector
  net start RCSCollector
) ELSE (
  net %1 RCSCollector
)
