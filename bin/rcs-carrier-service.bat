@echo off

IF %1 == restart (
  net stop RCSCarrier
  net start RCSCarrier
) ELSE (
  net %1 RCSCarrier
)
