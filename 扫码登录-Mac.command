#!/bin/bash
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
echo "======================================================"
echo "正在生成微信登录二维码，请稍候..."
echo "二维码出现后，请使用手机微信「扫一扫」并在手机上确认登录。"
echo "======================================================"
echo ""
openclaw channels login --channel openclaw-weixin
echo ""
read -r -p "按回车键关闭窗口..." _
