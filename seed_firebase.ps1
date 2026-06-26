# ============================================================
# SEED SCRIPT - Popula Firebase Firestore con datos iniciales
# Proyecto: restaurant1-98
# ============================================================

$PROJECT_ID = "restaurant1-98"
$API_KEY = "AIzaSyBT0RsyYbyrrX_SScm1QtfM1suRJrqBY9w"
$BASE_URL = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents"

function Write-Step($msg) {
    Write-Host "`n>>> $msg" -ForegroundColor Cyan
}

function Write-OK($msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-ERR($msg) {
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
}

Write-Host "`n============================================" -ForegroundColor Yellow
Write-Host "  FIREBASE SEED - ServeSync / restaurant1-98" -ForegroundColor Yellow
Write-Host "============================================`n" -ForegroundColor Yellow

# ─── CREAR MESEROS ──────────────────────────────────────────

Write-Step "Creando coleccion 'meseros'..."

$meseros = @(
    @{
        id     = "M001"
        docId  = "M001"
        nombre = "Carlos Lopez"
        pin    = "1234"
        activo = $true
    },
    @{
        id     = "M002"
        docId  = "M002"
        nombre = "Ana Garcia"
        pin    = "5678"
        activo = $true
    },
    @{
        id     = "ADMIN"
        docId  = "ADMIN"
        nombre = "Administrador"
        pin    = ""
        activo = $true
    }
)

foreach ($m in $meseros) {
    $body = @{
        fields = @{
            id     = @{ stringValue = $m.id }
            nombre = @{ stringValue = $m.nombre }
            pin    = @{ stringValue = $m.pin }
            activo = @{ booleanValue = $m.activo }
        }
    } | ConvertTo-Json -Depth 5

    $url = "$BASE_URL/meseros/$($m.docId)?key=$API_KEY"
    try {
        $response = Invoke-RestMethod -Method Patch -Uri $url `
            -ContentType "application/json" `
            -Body $body `
            -ErrorAction Stop
        Write-OK "Mesero $($m.docId) ($($m.nombre)) creado"
    }
    catch {
        Write-ERR "Error creando $($m.docId): $($_.Exception.Message)"
    }
}

# ─── CREAR MESAS ────────────────────────────────────────────

Write-Step "Creando coleccion 'mesas'..."

$mesas = @(
    @{ numero = 1;  capacidad = 2;  status = "libre" },
    @{ numero = 2;  capacidad = 4;  status = "libre" },
    @{ numero = 3;  capacidad = 4;  status = "libre" },
    @{ numero = 4;  capacidad = 6;  status = "libre" },
    @{ numero = 5;  capacidad = 6;  status = "libre" },
    @{ numero = 6;  capacidad = 2;  status = "libre" },
    @{ numero = 7;  capacidad = 8;  status = "libre" },
    @{ numero = 8;  capacidad = 4;  status = "libre" },
    @{ numero = 9;  capacidad = 4;  status = "libre" },
    @{ numero = 10; capacidad = 10; status = "libre" }
)

foreach ($mesa in $mesas) {
    $body = @{
        fields = @{
            numero    = @{ integerValue = $mesa.numero }
            capacidad = @{ integerValue = $mesa.capacidad }
            status    = @{ stringValue  = $mesa.status }
        }
    } | ConvertTo-Json -Depth 5

    # Usar PATCH con ID fijo para mesas (mesa1, mesa2, etc.)
    $docId = "mesa$($mesa.numero)"
    $url = "$BASE_URL/mesas/$($docId)?key=$API_KEY"
    try {
        $response = Invoke-RestMethod -Method Patch -Uri $url `
            -ContentType "application/json" `
            -Body $body `
            -ErrorAction Stop
        Write-OK "Mesa $($mesa.numero) (cap. $($mesa.capacidad)) creada"
    }
    catch {
        Write-ERR "Error creando mesa $($mesa.numero): $($_.Exception.Message)"
    }
}

Write-Host "`n============================================" -ForegroundColor Yellow
Write-Host "  SEED COMPLETADO" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "`nAhora puedes correr la app con: flutter run" -ForegroundColor White
Write-Host "Credenciales de acceso:" -ForegroundColor White
Write-Host "  ID: M001   PIN: 1234  -> Carlos Lopez" -ForegroundColor Cyan
Write-Host "  ID: M002   PIN: 5678  -> Ana Garcia" -ForegroundColor Cyan
Write-Host "  ID: ADMIN  (sin PIN)  -> Administrador`n" -ForegroundColor Cyan
