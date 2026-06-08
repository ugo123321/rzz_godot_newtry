# 清理 sucai 素材目录中的 macOS 垃圾文件（__MACOSX、._*）
$root = Join-Path (Split-Path $PSScriptRoot -Parent) "assets"
if (-not (Test-Path $root)) {
    $root = "D:\workspace\godot1\sucai"
}
Get-ChildItem -Path $root -Recurse -Directory -Filter "__MACOSX" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force
Get-ChildItem -Path $root -Recurse -File -Filter "._*" -ErrorAction SilentlyContinue |
    Remove-Item -Force
Write-Host "Cleaned macOS junk under: $root"
