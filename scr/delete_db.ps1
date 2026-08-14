# delete_db.ps1 – Deletes the database so it's recreated
$dbPath = "C:\Users\itsme\Documents\Codex\2026-07-08\supermart_pos_clean\.dart_tool\sqflite_common_ffi\databases\super_mart_pos.db"
if (Test-Path $dbPath) {
    Remove-Item -Force $dbPath
    Write-Host "Database deleted. It will be recreated on next run." -ForegroundColor Green
} else {
    Write-Host "Database not found at $dbPath" -ForegroundColor Yellow
}