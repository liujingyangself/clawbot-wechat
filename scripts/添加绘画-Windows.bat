@echo off
chcp 65001 >nul
title 微信 AI 助手 - 开通画图
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0add-drawing.ps1"
pause
