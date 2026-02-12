# PowerShell script to build WoW Sim Mists of Pandaria on Windows

$ErrorActionPreference = "Stop"

Write-Host "--- Step 1: Installing dependencies ---" -ForegroundColor Cyan
npm install

Write-Host "`n--- Step 2: Generating Protobuf files ---" -ForegroundColor Cyan
# Ensure Go bin is in PATH
$goPath = go env GOPATH
if ($goPath) {
    $env:PATH += ";$goPath\bin"
}

# Ensure directories exist
if (!(Test-Path "ui/core/proto")) { New-Item -ItemType Directory -Force -Path "ui/core/proto" }
if (!(Test-Path "sim/core/proto")) { New-Item -ItemType Directory -Force -Path "sim/core/proto" }

# Generate TypeScript protos
Write-Host "Generating TS protos..."
npx protoc --ts_opt generate_dependencies --ts_out ui/core/proto --proto_path proto proto/api.proto proto/test.proto proto/ui.proto

# Generate Go protos (requires protoc-gen-go in PATH)
# If you don't have it, this step might fail.
# You can download it via: go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
Write-Host "Generating Go protos..."
try {
    # Check if protoc-gen-go is available
    if (Get-Command "protoc-gen-go" -ErrorAction SilentlyContinue) {
        $protoFiles = Get-ChildItem -Path "proto" -Filter "*.proto" | ForEach-Object { "proto/$($_.Name)" }
        npx protoc "--proto_path=proto" "--go_out=sim/core" $protoFiles
    } else {
        Write-Warning "protoc-gen-go not found. Skipping Go proto generation. If .pb.go files are missing, the build will fail."
        Write-Host "You can install it with: go install google.golang.org/protobuf/cmd/protoc-gen-go@latest"
    }
} catch {
    Write-Warning "Failed to generate Go protos. Make sure 'protoc-gen-go' is in your PATH."
}

Write-Host "`n--- Step 3: Generating ui/core/index.ts ---" -ForegroundColor Cyan
$files = Get-ChildItem -Path "ui/core" -Filter "*.ts" -Recurse | Where-Object { $_.Name -ne "index.ts" -and $_.FullName -notlike "*\proto\*" }
$indexContent = $files | ForEach-Object {
    $relativePath = Resolve-Path $_.FullName -Relative
    # Resolve-Path -Relative might return path starting with .\
    $cleanPath = $relativePath -replace "^\.\\", ""
    # We want path relative to ui/core
    # If the script is run from root, $cleanPath starts with ui\core\
    $corePath = $cleanPath -replace "^ui\\core\\", ""
    $importPath = $corePath -replace "\\", "/" -replace "\.ts$", ""
    "import ""./$importPath"";"
}
$indexContent | Out-File -FilePath "ui/core/index.ts" -Encoding utf8 -NoNewline

Write-Host "`n--- Step 3.5: Generating spec index.html files ---" -ForegroundColor Cyan
$template = Get-Content "ui/index_template.html" -Raw
$specs = @(
    "death_knight/blood", "death_knight/frost", "death_knight/unholy",
    "druid/balance", "druid/feral", "druid/guardian", "druid/restoration",
    "hunter/beast_mastery", "hunter/marksmanship", "hunter/survival",
    "mage/arcane", "mage/fire", "mage/frost",
    "monk/brewmaster", "monk/mistweaver", "monk/windwalker",
    "paladin/holy", "paladin/protection", "paladin/retribution",
    "priest/discipline", "priest/holy", "priest/shadow",
    "rogue/assassination", "rogue/combat", "rogue/subtlety",
    "shaman/elemental", "shaman/enhancement", "shaman/restoration",
    "warlock/affliction", "warlock/demonology", "warlock/destruction",
    "warrior/arms", "warrior/fury", "warrior/protection",
    "raid/full"
)
foreach ($specPath in $specs) {
    $parts = $specPath -split "/"
    $class = $parts[0]
    $spec = $parts[1]

    $targetDir = "ui/$specPath"
    if (!(Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir }
    $content = $template.Replace("@@CLASS@@", $class).Replace("@@SPEC@@", $spec)
    $content | Out-File -FilePath "$targetDir/index.html" -Encoding utf8 -NoNewline
}

Write-Host "`n--- Step 4: Building UI ---" -ForegroundColor Cyan
npx tsx vite.build-workers.mts
npx vite build

Write-Host "`n--- Step 5: Preparing binary_dist ---" -ForegroundColor Cyan
if (Test-Path "binary_dist") { Remove-Item -Recurse -Force "binary_dist" }
New-Item -ItemType Directory -Force -Path "binary_dist/mop"
New-Item -ItemType File -Force -Path "binary_dist/mop/embedded" | Out-Null
Copy-Item -Path "sim/web/dist.go.tmpl" -Destination "binary_dist/dist.go"
Copy-Item -Recurse -Path "dist/mop/*" -Destination "binary_dist/mop/"

# Remove large/unnecessary files from embedded distribution
if (Test-Path "binary_dist/mop/lib.wasm") { Remove-Item "binary_dist/mop/lib.wasm" }
if (Test-Path "binary_dist/mop/assets/database/db.bin") { Remove-Item "binary_dist/mop/assets/database/db.bin" }

Write-Host "`n--- Step 6: Building Go executable ---" -ForegroundColor Cyan
$env:GOOS = "windows"
$env:GOARCH = "amd64"
go build -o wowsimmop.exe ./sim/web/main.go

Write-Host "`n--- Done! ---" -ForegroundColor Green
Write-Host "Executable created: wowsimmop.exe"
