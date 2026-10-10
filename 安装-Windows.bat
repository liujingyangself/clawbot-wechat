@echo off
chcp 65001 >nul
title 微信 AI 助手 - 安装

rem 不需要管理员权限：所有东西都装在当前用户目录下。
rem 如果提权运行，后台服务会注册到管理员账户，反而连不上你的微信。

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1"

if %errorlevel% neq 0 (
    echo.
    echo 安装没能正常结束。日志在：
    echo %LOCALAPPDATA%\clawbot-wechat\install.log
    echo.
)
pause
