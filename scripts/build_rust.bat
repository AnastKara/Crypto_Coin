@echo off
setlocal enabledelayedexpansion

:: Set PATH to include Rust and MinGW
set "PATH=C:\Users\user\.cargo\bin;C:\msys64\ucrt64\bin;%PATH%"

:: Navigate to project root
cd /d "C:\Users\user\Documents\Crypto_Coin"

:: Clean and build
echo Cleaning previous build...
cargo clean

echo Building with GNU target...
cargo build --target x86_64-pc-windows-gnu 2>&1

if %ERRORLEVEL% EQU 0 (
    echo Build successful!
) else (
    echo Build failed with error level %ERRORLEVEL%
)

endlocal
