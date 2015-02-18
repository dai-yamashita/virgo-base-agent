@ECHO off

IF NOT "x%1" == "x" GOTO :%1

:virgo
ECHO "Building virgo"
IF NOT EXIST lit.exe CALL Make.bat lit
lit.exe make
GOTO :end

:lit
ECHO "Building lit"
git clone --recursive --depth 1 https://github.com/luvit/lit.git lit
SET LUVI_APP=lit/
SET LUVI_TARGET=lit.exe
lit\luvi-binaries\Windows\luvi.exe
SET "LUVI_APP="
SET "LUVI_TARGET="
GOTO :end

:test
SET "LUVI_APP="
SET "LUVI_TARGET="
CALL Make.bat virgo
virgo.exe tests\run.lua
GOTO :end

:clean
IF EXIST virgo.exe DEL /F /Q virgo-base.exe
IF EXIST lit.exe DEL /F /Q lit.exe
IF EXIST lit RMDIR /S /Q lit
IF EXIST luvi-binaries RMDIR /S /Q luvi-binaries

:end

