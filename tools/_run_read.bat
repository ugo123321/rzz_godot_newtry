@echo off
copy "D:\workspace\godot1\rzz_godot\弓箭传说2参考.xlsx" "D:\workspace\godot1\rzz_godot\tools\_ref_copy.xlsx" >nul
python -c "import openpyxl; wb=openpyxl.load_workbook('D:/workspace/godot1/rzz_godot/tools/_ref_copy.xlsx'); print('Sheets:', wb.sheetnames); [print(f'\n=== {n} ===') or [print(r) for r in ws.iter_rows(min_row=1, max_row=min(ws.max_row, 100), values_only=True)] for n, ws in [(n, wb[n]) for n in wb.sheetnames]]" > "D:\workspace\godot1\rzz_godot\tools\_excel_output.txt" 2>&1
del "D:\workspace\godot1\rzz_godot\tools\_ref_copy.xlsx"