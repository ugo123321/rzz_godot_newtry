@echo off
chcp 65001 >nul
setlocal

set "GODOT=%GODOT_CONSOLE%"
if not defined GODOT set "GODOT=D:\godot\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
set "PROJECT=%~dp0.."
set "OUT=%PROJECT%\build\web\index.html"

if not exist "%GODOT%" (
  echo 找不到 Godot：%GODOT%
  echo 请设置环境变量 GODOT_CONSOLE 指向 Godot *_console.exe
  exit /b 1
)

if not exist "%PROJECT%\build\web" mkdir "%PROJECT%\build\web"

echo 正在导出 Web 版本到 build\web ...
echo Godot: %GODOT%
echo.

"%GODOT%" --headless --path "%PROJECT%" --export-release "Web" "%OUT%"
if errorlevel 1 (
  echo.
  echo 导出失败。请确认已在 Godot 编辑器中安装 Web 导出模板：
  echo   编辑器 -^> 管理导出模板 -^> 下载并安装
  exit /b 1
)

echo.
echo 导出完成：build\web\
echo 本地预览：在 build\web 目录运行 npx serve .
echo Vercel：将 Root Directory 设为 build/web 后部署
