@echo off
chcp 65001 >nul
title 微信 AI 助手 - 扫码登录微信

cd /d "%~dp0"
echo ======================================================
echo 正在生成微信登录二维码，请稍候...
echo 二维码出现后，请使用手机微信「扫一扫」并在手机上确认登录。
echo ======================================================
echo.
openclaw channels login --channel openclaw-weixin
echo.
pause
