# Crypto_Coin Development Environment Setup Script (PowerShell)
# Install required toolchains for development

Write-Host "Crypto_Coin Development Setup" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green

# 1. Install Rust via rustup
Write-Host "`n[1/3] Installing Rust toolchain..." -ForegroundColor Yellow
$rustup = Get-Command "rustup" -ErrorAction SilentlyContinue
if (-not $rustup) {
    Write-Host "Downloading rustup-init.exe..."
    Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -OutFile "$env:TEMP\rustup-init.exe"
    Start-Process -Wait -FilePath "$env:TEMP\rustup-init.exe" -ArgumentList "-y --default-toolchain stable"
    # Add to PATH for current session
    $env:Path += ";$env:USERPROFILE\.cargo\bin"
    Write-Host "Rust installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Rust already installed. Updating..."
    rustup update stable
}

# 2. Install Haskell via GHCup
Write-Host "`n[2/3] Installing Haskell toolchain..." -ForegroundColor Yellow
$ghcup = Get-Command "ghcup" -ErrorAction SilentlyContinue
if (-not $ghcup) {
    Write-Host "Downloading GHCup installer..."
    Invoke-WebRequest -Uri "https://downloads.haskell.org/~ghcup/x86_64-mingw64/ghcup.exe" -OutFile "$env:TEMP\ghcup.exe"
    Start-Process -Wait -FilePath "$env:TEMP\ghcup.exe" -ArgumentList "install ghc 9.6.5"
    Start-Process -Wait -FilePath "$env:TEMP\ghcup.exe" -ArgumentList "install cabal 3.10.3.0"
    Start-Process -Wait -FilePath "$env:TEMP\ghcup.exe" -ArgumentList "install stack 2.15.5"
    Write-Host "Haskell installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Haskell already installed. Updating..."
    ghcup upgrade
}

# 3. Build Rust workspace
Write-Host "`n[3/3] Building Rust workspace..." -ForegroundColor Yellow
Set-Location (Split-Path $PSScriptRoot -Parent)
cargo build --release

Write-Host "`nSetup complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Build Rust components:  cargo build --release"
Write-Host "2. Build Haskell formal:   cd formal-protocol && cabal build all"
Write-Host "3. Run Rust tests:         cargo test"
Write-Host "4. Run Haskell tests:      cd formal-protocol && cabal test all"

