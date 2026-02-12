# PowerShell script to build WoW Sim Mists of Pandaria on Windows

$ErrorActionPreference = "Stop"

Write-Host "--- Step 1: Installing dependencies ---" -ForegroundColor Cyan
npm install

Write-Host "`n--- Step 2: Generating Protobuf files ---" -ForegroundColor Cyan
# Ensure directories exist
if (!(Test-Path "ui/core/proto")) { New-Item -ItemType Directory -Force -Path "ui/core/proto" }
if (!(Test-Path "sim/core/proto")) { New-Item -ItemType Directory -Force -Path "sim/core/proto" }

# Generate TypeScript protos
Write-Host "Generating TS protos..."
npx protoc --ts_opt generate_dependencies --ts_out ui/core/proto --proto_path=. proto/api.proto proto/test.proto proto/ui.proto

# Generate Go protos
Write-Host "Generating Go protos..."
# We try to use system protoc if available, otherwise npx protoc
$protocCmd = "protoc"
if (!(Get-Command "protoc" -ErrorAction SilentlyContinue)) {
    $protocCmd = "npx protoc"
}

try {
    # Check if protoc-gen-go is available
    if (Get-Command "protoc-gen-go" -ErrorAction SilentlyContinue) {
        if ($protocCmd -eq "npx protoc") {
            npx protoc --proto_path=. --go_out=./sim/core proto/api.proto proto/test.proto proto/ui.proto proto/common.proto proto/apl.proto proto/db.proto proto/spell.proto
        } else {
            protoc --proto_path=. --go_out=./sim/core proto/api.proto proto/test.proto proto/ui.proto proto/common.proto proto/apl.proto proto/db.proto proto/spell.proto
        }
    } else {
        Write-Warning "protoc-gen-go not found. Skipping Go proto generation. If .pb.go files are missing, the build will fail."
        Write-Host "You can install it with: go install google.golang.org/protobuf/cmd/protoc-gen-go@latest"
    }
} catch {
    Write-Warning "Failed to generate Go protos: $($_.Exception.Message)"
}

Write-Host "`n--- Step 3: Generating ui/core/index.ts ---" -ForegroundColor Cyan
$coreDir = Join-Path (Get-Location) "ui/core"
$files = Get-ChildItem -Path $coreDir -Filter "*.ts" -Recurse | Where-Object {
    $_.Name -ne "index.ts" -and
    $_.FullName -notlike "*\proto\*" -and
    $_.FullName -notlike "*\node_modules\*"
}

$importLines = New-Object System.Collections.Generic.List[string]
foreach ($file in $files) {
    # Calculate path relative to ui/core
    $relPath = [System.IO.Path]::GetRelativePath($coreDir, $file.FullName)
    $importPath = $relPath -replace "\\", "/" -replace "\.ts$", ""
    $importLines.Add("import ""./$importPath"";")
}

$indexContent = [string]::Join("`n", $importLines)
if ($indexContent) { $indexContent += "`n" }
$indexContent | Set-Content -Path "ui/core/index.ts" -NoNewline

Write-Host "`n--- Step 4: Building UI ---" -ForegroundColor Cyan
# Ensure dist directory exists for workers
if (!(Test-Path "dist/mop")) { New-Item -ItemType Directory -Force -Path "dist/mop" }
npx tsx vite.build-workers.mts
npx vite build

Write-Host "`n--- Step 5: Preparing binary_dist ---" -ForegroundColor Cyan
if (Test-Path "binary_dist") { Remove-Item -Recurse -Force "binary_dist" }
New-Item -ItemType Directory -Force -Path "binary_dist/mop"
New-Item -ItemType File -Force -Path "binary_dist/mop/embedded" | Out-Null
Copy-Item -Path "sim/web/dist.go.tmpl" -Destination "binary_dist/dist.go"
if (Test-Path "dist/mop/*") {
    Copy-Item -Recurse -Path "dist/mop/*" -Destination "binary_dist/mop/"
}

# Remove large/unnecessary files from embedded distribution
if (Test-Path "binary_dist/mop/lib.wasm") { Remove-Item "binary_dist/mop/lib.wasm" }
if (Test-Path "binary_dist/mop/assets/database/db.bin") { Remove-Item "binary_dist/mop/assets/database/db.bin" }

Write-Host "`n--- Step 6: Building Go executable ---" -ForegroundColor Cyan
$env:GOOS = "windows"
$env:GOARCH = "amd64"
go build -o wowsimmop.exe ./sim/web/main.go

Write-Host "`n--- Done! ---" -ForegroundColor Green
Write-Host "Executable created: wowsimmop.exe"
