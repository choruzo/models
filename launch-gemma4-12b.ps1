# launch-gemma4-12b.ps1 - Lanzador de Gemma 4 12B con llama.cpp
# Uso:
#   .\launch-gemma4-12b.ps1 [-Context 32k|42k|64k] [-Port 8080] [-Threads 12] [-UseMtp]

param(
    [ValidateSet("32k", "42k", "64k")]
    [string]$Context = "42k",

    [int]$Port = 8080,

    [int]$Threads = 12,

    [switch]$UseMtp
)

# Rutas
$LlamaBin       = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath      = "G:\models\gemma-4-12b-it-UD-Q6_K_XL.gguf"
$DraftModelPath = "G:\models\gemma-4-12b-it-Q8_0-MTP.gguf"

if (-not (Test-Path $LlamaBin))  { Write-Error "No se encuentra llama-server en: $LlamaBin"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo en: $ModelPath";   exit 1 }

$MtpEnabled = $false
if ($UseMtp) {
    if (Test-Path $DraftModelPath) {
        $MtpEnabled = $true
    } else {
        Write-Warning "No se encuentra modelo MTP en: $DraftModelPath. Se inicia sin MTP."
    }
}

# Perfiles de contexto priorizando estabilidad en 16 GB VRAM
switch ($Context) {
    "32k" {
        $CtxSize   = 32768
        $KvTypeK   = "q8_0"
        $KvTypeV   = "q8_0"
        $BatchSize = 768
        $UBatch    = 512
    }
    "42k" {
        $CtxSize   = 43008
        $KvTypeK   = "q4_0"
        $KvTypeV   = "q4_0"
        $BatchSize = 768
        $UBatch    = 512
    }
    "64k" {
        $CtxSize   = 65536
        $KvTypeK   = "q4_0"
        $KvTypeV   = "q4_0"
        $BatchSize = 512
        $UBatch    = 256
    }
}

Write-Host ""
Write-Host "  Modelo      : $ModelPath"
Write-Host "  Contexto    : $CtxSize tokens ($Context)"
Write-Host "  KV cache    : $KvTypeK / $KvTypeV"
Write-Host "  Batch/UB    : $BatchSize / $UBatch"
Write-Host "  Threads     : $Threads"
Write-Host "  Puerto      : $Port"
Write-Host "  MTP draft   : $(if ($MtpEnabled) { 'on' } else { 'off' })"
if ($MtpEnabled) { Write-Host "  Draft model : $DraftModelPath" }
Write-Host ""

$args = @(
    "--model",                $ModelPath,
    "--alias",                "gemma-4-12b",
    "--jinja",
    "--reasoning",            "auto",
    "--ctx-size",             $CtxSize,
    "--cache-type-k",         $KvTypeK,
    "--cache-type-v",         $KvTypeV,
    "--flash-attn",           "on",
    "--batch-size",           $BatchSize,
    "--ubatch-size",          $UBatch,
    "--threads",              $Threads,
    "--threads-batch",        $Threads,
    "--n-gpu-layers",         "all",
    "--fit",                  "on",
    "--fit-target",           "1536",
    "--parallel",             "1",
    "--cont-batching",
    "--kv-unified",
    "--cache-prompt",
    "--host",                 "0.0.0.0",
    "--port",                 $Port,
    "--metrics",
    "--mlock"
)

if ($MtpEnabled) {
    $args += @(
        "--model-draft",          $DraftModelPath,
        "--spec-type",            "draft-mtp",
        "--spec-draft-n-max",     "4",
        "--spec-draft-n-min",     "1",
        "--n-gpu-layers-draft",   "all"
    )
}

& $LlamaBin @args
