# launch-qwen.ps1 — Lanzador de Qwen3.6-27B-IQ4_XS con llama.cpp
# Uso: .\launch-qwen.ps1 [-Context 32k|64k] [-Port 8080] [-Threads 8]

param(
    [ValidateSet("32k", "64k")]
    [string]$Context = "32k",

    [int]$Port = 8080,

    [int]$Threads = 8
)

# ─── Rutas — ajusta según tu instalación ────────────────────────────────────
$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\Qwen3.6-27B-UD-Q3_K_XL.gguf"
# ─────────────────────────────────────────────────────────────────────────────

# Validar que los archivos existen
if (-not (Test-Path $LlamaBin))  { Write-Error "No se encuentra llama-server en: $LlamaBin"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo en: $ModelPath";   exit 1 }

# Configuración por modo de contexto
switch ($Context) {
    "32k" {
        $CtxSize    = 32768
        $GpuLayers  = 99        # modelo entero en VRAM (~14.5 GB)
        $KvTypeK    = "q4_0"    # KV cache cuantizado → ~0.6 GB para 32K
        $KvTypeV    = "q4_0"
    }
    "64k" {
        $CtxSize    = 65536
        $GpuLayers  = 30        # baja 6 capas a CPU, libera ~2.5 GB de VRAM
        $KvTypeK    = "q8_0"    # mejor calidad en contexto largo
        $KvTypeV    = "q8_0"
    }
}

Write-Host ""
Write-Host "  Modelo  : $ModelPath"
Write-Host "  Contexto: $CtxSize tokens"
Write-Host "  GPU     : $GpuLayers capas en VRAM"
Write-Host "  KV cache: $KvTypeK / $KvTypeV"
Write-Host "  Puerto  : $Port"
Write-Host ""

& $LlamaBin `
    --model          $ModelPath `
    --ctx-size       $CtxSize `
    --n-gpu-layers   $GpuLayers `
    --cache-type-k   $KvTypeK `
    --cache-type-v   $KvTypeV `
    --threads        $Threads `
    --host           "127.0.0.1" `
    --port           $Port `
    --flash-attn     on `
    --mlock
