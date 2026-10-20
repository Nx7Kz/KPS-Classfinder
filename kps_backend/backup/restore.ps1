<#
กู้คืนข้อมูลจากไฟล์ backup ที่สร้างด้วย backup.ps1
คำเตือน: จะเขียนทับฐานข้อมูลและไฟล์ที่อัปโหลดปัจจุบันทั้งหมด

วิธีใช้:
  .\restore.ps1 -ZipPath .\backups\kps-backup_2026-10-20_153000.zip
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath
)

$ErrorActionPreference = "Stop"
$ComposeDir = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path $ZipPath)) {
    throw "ไม่พบไฟล์: $ZipPath"
}

Write-Host "คำเตือน: การกู้คืนจะเขียนทับฐานข้อมูลและไฟล์อัปโหลดปัจจุบันทั้งหมด" -ForegroundColor Yellow
$confirm = Read-Host "พิมพ์ 'yes' เพื่อยืนยัน"
if ($confirm -ne "yes") {
    Write-Host "ยกเลิก"
    exit
}

$extractDir = Join-Path $env:TEMP "kps-restore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

try {
    Write-Host "1/3 กำลังแตกไฟล์..."
    Expand-Archive -Path $ZipPath -DestinationPath $extractDir -Force

    Write-Host "2/3 กำลังกู้คืนฐานข้อมูล..."
    $dbContainer = (docker compose -f "$ComposeDir\docker-compose.yml" ps -q db)
    if (-not $dbContainer) {
        throw "ไม่พบ container ของ db — ต้องรัน 'docker compose up -d' ที่ kps_backend ก่อน"
    }
    $sqlPath = Join-Path $extractDir "kps_classfinder.sql"
    Get-Content $sqlPath -Raw | docker exec -i $dbContainer sh -c "exec mysql -u root kps_classfinder"

    Write-Host "3/3 กำลังกู้คืนไฟล์ที่อัปโหลด..."
    $uploadDirs = @("panoramas", "floorplans", "covers", "tour-images")
    foreach ($dir in $uploadDirs) {
        $src = Join-Path $extractDir "uploads\$dir"
        $dest = Join-Path $ComposeDir "public\$dir"
        if (Test-Path $src) {
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -Path "$src\*" -Destination $dest -Recurse -Force
        }
    }

    Write-Host "กู้คืนเสร็จแล้ว" -ForegroundColor Green
}
finally {
    Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
}
