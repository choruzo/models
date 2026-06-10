# launch-gpt-oss-20b.ps1 - Lanzador de gpt-oss-20b-Q5_K_M con llama.cpp
# Uso:
#   .\launch-gpt-oss-20b.ps1 [-Profile speed|balanced|quality|long] [-Port 8080] [-Threads 12]

param(
    [ValidateSet("speed", "balanced", "quality", "long")]
    [string]$Profile = "balanced",

    [int]$Port = 8080,

    [int]$Threads = 12
)

# Rutas
$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\gpt-oss-20b-Q5_K_M.gguf"

if (-not (Test-Path $LlamaBin))  { Write-Error "No se encuentra llama-server en: $LlamaBin"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo en: $ModelPath";   exit 1 }

# Perfiles pensados para 16 GB VRAM (RTX 5060 Ti)
# Nota: --fit on ajusta automaticamente capas/contexto para evitar OOM.
switch ($Profile) {
    "speed" {
        $CtxSize   = 16384
        $KvTypeK   = "q4_0"
        $KvTypeV   = "q4_0"
        $BatchSize = 1024
        $UBatch    = 512
        $Reasoning = "off"
    }
    "balanced" {
        $CtxSize   = 32768
        $KvTypeK   = "q4_0"
        $KvTypeV   = "q4_0"
        $BatchSize = 768
        $UBatch    = 512
        $Reasoning = "auto"
    }
    "quality" {
        $CtxSize   = 32768
        $KvTypeK   = "q8_0"
        $KvTypeV   = "q8_0"
        $BatchSize = 512
        $UBatch    = 512
        $Reasoning = "auto"
    }
    "long" {
        $CtxSize   = 65536
        $KvTypeK   = "q4_0"
        $KvTypeV   = "q4_0"
        $BatchSize = 512
        $UBatch    = 256
        $Reasoning = "off"
    }
}

Write-Host ""
Write-Host "  Modelo     : $ModelPath"
Write-Host "  Perfil     : $Profile"
Write-Host "  Contexto   : $CtxSize tokens"
Write-Host "  KV cache   : $KvTypeK / $KvTypeV"
Write-Host "  Batch/UB   : $BatchSize / $UBatch"
Write-Host "  Reasoning  : $Reasoning"
Write-Host "  Threads    : $Threads"
Write-Host "  Puerto     : $Port"
Write-Host ""

$args = @(
    "--model",                $ModelPath,
    "--alias",                "gpt-oss-20b",
    "--chat-template",        "gpt-oss",
    "--jinja",
    "--reasoning",            $Reasoning,
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
    "--cache-prompt",
    "--cache-reuse",          "256",
    "--host",                 "127.0.0.1",
    "--port",                 $Port,
    "--metrics",
    "--mlock"
)

& $LlamaBin @args
