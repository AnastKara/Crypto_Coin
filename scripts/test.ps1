# Crypto_Coin Test Script (PowerShell)

Write-Host "Crypto_Coin Test Suite" -ForegroundColor Green
Write-Host "======================" -ForegroundColor Green

$rootDir = Split-Path $PSScriptRoot -Parent

# 1. Run Rust tests
Write-Host "`n[1/2] Running Rust tests..." -ForegroundColor Yellow
Set-Location $rootDir
$env:RUST_BACKTRACE = "1"
cargo test 2>&1 | ForEach-Object { $_ }

if ($LASTEXITCODE -ne 0) {
    Write-Host "Rust tests FAILED!" -ForegroundColor Red
    exit 1
}
Write-Host "Rust tests passed!" -ForegroundColor Green

# 2. Run Haskell tests (if Stack available)
Write-Host "`n[2/2] Running Haskell tests..." -ForegroundColor Yellow
$stack = Get-Command "stack" -ErrorAction SilentlyContinue
if ($stack) {
    Set-Location "$rootDir/formal-protocol"
    stack test 2>&1 | ForEach-Object { $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Haskell tests FAILED!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Haskell tests passed!" -ForegroundColor Green
} else {
    Write-Host "Stack not found. Skipping Haskell tests." -ForegroundColor Yellow
}

Write-Host "`nAll tests passed!" -ForegroundColor Green

