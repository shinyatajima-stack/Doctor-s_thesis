@echo off
rem  thesis.tex を Typst で 1 回ビルド → thesis-typst.pdf
chcp 65001 >nul
cd /d "%~dp0"
python tex2typst\build.py thesis.tex %*
if errorlevel 1 pause
