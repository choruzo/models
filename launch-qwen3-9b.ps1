# launch-qwen3-9b.ps1 — Qwen3-9B Q8_0 con llama.cpp · máximo contexto en 16 GB VRAM
# Uso: .\launch-qwen3-9b.ps1 [-Context 32k|64k|128k] [-Port 8080] [-Threads 8]

param(
    [ValidateSet("32k", "64k", "128k")]
    [string]$Context = "64k",

    [int]$Port    = 8080,
    [int]$Threads = 8
)

# ─── Rutas ───────────────────────────────────────────────────────────────────
$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\Qwen3.5-9B-Q8_0.gguf"
# ─────────────────────────────────────────────────────────────────────────────

if (-not (Test-Path $LlamaBin))  { Write-Error "No se encuentra llama-server en: $LlamaBin"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo en: $ModelPath";   exit 1 }

# ─── Presupuesto VRAM (16 GB) ────────────────────────────────────────────────
#  Pesos Q8_0 ~9.5 GB + overhead ~0.5 GB = ~10 GB fijos
#  Resto disponible para KV cache: ~6 GB
#
#  KV por token (32 capas, 8 KV heads, dim 128):
#    q8_0 → 64 KB/tok  →  6 GB ≈  93 K tokens max
#    q4_0 → 32 KB/tok  →  6 GB ≈ 187 K tokens max
# ─────────────────────────────────────────────────────────────────────────────
switch ($Context) {
    "32k" {
        $CtxSize   = 32768
        $GpuLayers = 99       # modelo entero en VRAM
        $KvTypeK   = "q8_0"   # máxima calidad; KV ~2 GB
        $KvTypeV   = "q8_0"
        $RopeScale = $null    # contexto nativo, sin escalado
    }
    "64k" {
        $CtxSize   = 65536
        $GpuLayers = 99       # modelo entero en VRAM; KV ~4 GB → total ~14 GB
        $KvTypeK   = "q8_0"
        $KvTypeV   = "q8_0"
        $RopeScale = $null    # Qwen3 soporta 64K con YaRN interno
    }
    "128k" {
        $CtxSize   = 131072
        $GpuLayers = 99       # KV ~4 GB con q4_0 → total ~14 GB
        $KvTypeK   = "q4_0"   # q4_0 necesario para caber en 16 GB
        $KvTypeV   = "q4_0"
        $RopeScale = $null
    }
}

Write-Host ""
Write-Host "  Modelo   : $ModelPath"
Write-Host "  Contexto : $CtxSize tokens"
Write-Host "  GPU      : $GpuLayers capas en VRAM"
Write-Host "  KV cache : $KvTypeK / $KvTypeV"
Write-Host "  Puerto   : $Port"
Write-Host ""

$args = @(
    "--model",          $ModelPath,
    "--ctx-size",       $CtxSize,
    "--n-gpu-layers",   $GpuLayers,
    "--cache-type-k",   $KvTypeK,
    "--cache-type-v",   $KvTypeV,
    "--flash-attn",     "on",     # imprescindible para contexto largo
    "--threads",        $Threads,
    "--batch-size",     512,      # tokens procesados en paralelo (prefill)
    "--ubatch-size",    512,      # micro-batch; igual al batch-size es seguro
    "--host",           "127.0.0.1",
    "--port",           $Port,
    "--mlock"                     # bloquea el modelo en VRAM, evita swapping
)

& $LlamaBin @args
