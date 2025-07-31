$X64Path = "$PSScriptRoot\HLFindDevice-win-x64"
$X64ZipPath = "$PSScriptRoot\HLFindDevice-win-x64.zip"

$X86Path = "$PSScriptRoot\FindDevice-win-x86"
$X86ZipPath = "$PSScriptRoot\FindDevice-win-x86.zip"

switch ((Get-CimInstance -ClassName win32_operatingsystem).OSArchitecture -eq "64-bit") {
    $true {
        if (Test-Path $X64Path) {
            exit 0
        } 
        else {
            Invoke-WebRequest -Uri "https://github.com/lordhubert/HLFindDevice/releases/download/1.1.1/HLFindDevice-win-x64.zip" -OutFile $X64ZipPath
            Expand-Archive -LiteralPath $X64ZipPath -DestinationPath $X64Path -Force
            Remove-Item -Path $X64ZipPath
        }
    }
    $false {
        if (Test-Path $X86Path) {
            exit 0
        }
        else {
            Invoke-WebRequest -Uri "https://github.com/microsoft/FindDevice/releases/download/v1.0.0/FindDevice-win-x86.zip" -OutFile $X86ZipPath
            Expand-Archive -LiteralPath $X86ZipPath -DestinationPath $X86Path -Force
            Remove-Item -Path $X86ZipPath
        }
    }
}