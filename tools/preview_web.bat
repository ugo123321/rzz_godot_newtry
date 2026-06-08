@echo off
chcp 65001 >nul
echo 正在启动本地预览服务器...
echo 请不要直接双击 index.html，必须通过 http:// 访问。
echo.
python "%~dp0preview_web.py"
pause
