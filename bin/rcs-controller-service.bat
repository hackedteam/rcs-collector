@echo off

IF %1 == restart (
  net stop RCSController
  net start RCSController
) ELSE (
  net %1 RCSController
)
