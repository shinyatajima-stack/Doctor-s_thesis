@echo off
rem  .tex を保存するたびに自動で thesis-typst.pdf を更新（終了は Ctrl+C）
chcp 65001 >nul
cd /d "%~dp0"
python tex2typst\build.py thesis.tex --watch %*
pause
