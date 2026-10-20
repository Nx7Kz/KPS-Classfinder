<#
สำรองข้อมูลระบบ KPS Classfinder ทั้งฐานข้อมูล MySQL และไฟล์ที่อัปโหลดผ่านแดชบอร์ด
(ผังชั้น, รูปปก, ภาพ 360°, ภาพเดินชมอาคาร)

วิธีใช้:
  .\backup.ps1                  # backup ไปที่ .\kps_backend\backup\backups\
  .\backup.ps1 -OutDir D:\Backups  # backup ไปที่โฟลเดอร์อื่น (เช่น external drive)
  .\backup.ps1 -Keep 30         # เก็บไว้ 30 ชุดล่าสุด (ค่าเริ่มต้น 14)

ต้องมี docker compose ของ kps_backend รันอยู่ (service db ต้อง up)
#>
param(
    [string]$OutDir = "$PSScriptRoot\backups",
    [int]$Keep = 14
)

$ErrorActionPreference = "Stop"
$ComposeDir = Split-Path $PSScriptRoot -Parent

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$stagingDir = Join-Path $OutDir "staging_$timestamp"
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

try {
    Write-Host "1/3 กำลัง dump ฐานข้อมูล..."
    $dbContainer = (docker compose -f "$ComposeDir\docker-compose.yml" ps -q db)
    if (-not $dbContainer) {
        throw "ไม่พบ container ของ db — ต้องรัน 'docker compose up -d' ที่ kps_backend ก่อน"
    }
    $sqlPath = Join-Path $stagingDir "kps_classfinder.sql"
    docker exec $dbContainer sh -c "exec mysqldump -u root kps_classfinder" | Out-File -FilePath $sqlPath -Encoding utf8
    if ((Get-Item $sqlPath).Length -eq 0) {
        throw "mysqldump ได้ไฟล์เปล่า — ตรวจสอบว่า container db รันอยู่และฐานข้อมูลชื่อถูกต้อง"
    }

    Write-Host "2/3 กำลังคัดลอกไฟล์ที่อัปโหลด..."
    $uploadDirs = @("panoramas", "floorplans", "covers", "tour-images")
    foreach ($dir in $uploadDirs) {
        $src = Join-Path $ComposeDir "public\$dir"
        if (Test-Path $src) {
            $dest = Join-Path $stagingDir "uploads\$dir"
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -Path "$src\*" -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "3/3 กำลังบีบอัดไฟล์..."
    $zipPath = Join-Path $OutDir "kps-backup_$timestamp.zip"
    Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -CompressionLevel Optimal

    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "เสร็จแล้ว: $zipPath ($sizeMB MB)" -ForegroundColor Green
}
finally {
    Remove-Item -Recurse -Force $stagingDir -ErrorAction SilentlyContinue
}

# ลบ backup เก่าเกิน $Keep ชุด
$allBackups = Get-ChildItem -Path $OutDir -Filter "kps-backup_*.zip" | Sort-Object Name -Descending
if ($allBackups.Count -gt $Keep) {
    $toDelete = $allBackups | Select-Object -Skip $Keep
    foreach ($f in $toDelete) {
        Write-Host "ลบ backup เก่า: $($f.Name)"
        Remove-Item $f.FullName -Force
    }
}

Write-Host "มี backup เก็บไว้ทั้งหมด $([math]::Min($allBackups.Count, $Keep)) ชุด ที่ $OutDir"
