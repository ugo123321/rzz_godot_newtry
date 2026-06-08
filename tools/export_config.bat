@echo off
chcp 65001 >nul
echo 正在从 config\excel 读取配置并导出到 config\json ...
python "%~dp0export_config.py"
echo.
echo 导出完成。请在 Godot 里重新按 F5 运行游戏使配置生效。
echo 注意：请先保存并关闭 Excel，否则可能读到旧数据。
echo.
echo 若要重置 Excel 模板（会覆盖你的 Excel 修改）：
echo   python tools\export_config.py --init-excel
pause
