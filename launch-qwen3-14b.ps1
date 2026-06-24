# launch-qwen3-14b.ps1 - Qwen3 14B Q5_K_XL, contexto maximo GPU-only
#
# Perfil validado en una RTX 5060 Ti de 16 GB con llama.cpp b702:
#   - contexto nativo completo: 40 960 tokens
#   - pesos, KV cache y buffers de calculo en CUDA
#   - KV q5_1 para conservar calidad sin agotar la VRAM
#   - una unica secuencia para no dividir el contexto ni duplicar buffers
#
# Uso:
#   .\launch-qwen3-14b.ps1
#   .\launch-qwen3-14b.ps1 -Port 8080 -Reasoning auto

param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,

    [ValidateSet("auto", "on", "off")]
    [string]$Reasoning = "auto",

    [ValidateRange(12000, 16000)]
    [int]$MinFreeVramMiB = 13500
)

$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\Qwen3-14B-UD-Q5_K_XL.gguf"
$GpuIndex  = 0
$CtxSize   = 40960

if (-not (Test-Path -LiteralPath $LlamaBin -PathType Leaf)) {
    Write-Error "No se encuentra llama-server en: $LlamaBin"
    exit 1
}

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    Write-Error "No se encuentra el modelo en: $ModelPath"
    exit 1
}

# El perfil consume unos 12,4 GiB adicionales de VRAM. Exigir 13,5 GiB libres
# antes de cargar deja aproximadamente 1 GiB de margen para Windows y CUDA.
$NvidiaSmi = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue
if (-not $NvidiaSmi) {
    Write-Error "No se encuentra nvidia-smi.exe; no se puede verificar la VRAM libre."
    exit 1
}

$FreeVramRaw = & $NvidiaSmi.Source `
    "--query-gpu=memory.free" `
    "--format=csv,noheader,nounits" `
    "--id=$GpuIndex" 2>$null

$FreeVramMiB = 0
if (($LASTEXITCODE -ne 0) -or
    (-not [int]::TryParse(($FreeVramRaw | Select-Object -First 1).Trim(), [ref]$FreeVramMiB))) {
    Write-Error "nvidia-smi no ha devuelto una cantidad valida de VRAM libre."
    exit 1
}

if ($FreeVramMiB -lt $MinFreeVramMiB) {
    Write-Error "VRAM libre insuficiente: $FreeVramMiB MiB. Cierra aplicaciones que usen la GPU hasta disponer de al menos $MinFreeVramMiB MiB. No se permite fallback a RAM."
    exit 1
}

Write-Host ""
Write-Host "  Modelo          : $ModelPath"
Write-Host "  Alias           : qwen3-14b"
Write-Host "  Contexto        : $CtxSize tokens"
Write-Host "  KV cache        : q5_1 / q5_1"
Write-Host "  Razonamiento    : $Reasoning"
Write-Host "  VRAM libre      : $FreeVramMiB MiB"
Write-Host "  API             : http://127.0.0.1:$Port/v1"
Write-Host "  GPU-only        : estricto; sin fallback automatico a RAM"
Write-Host ""

$LlamaArgs = @(
    "--model",            $ModelPath,
    "--alias",            "qwen3-14b",
    "--jinja",
    "--reasoning",        $Reasoning,

    # Maximo contexto nativo del GGUF. Q5_1 ofrece mejor margen que Q8 y
    # bastante mas fidelidad que Q4 para una conversacion larga.
    "--ctx-size",         $CtxSize,
    "--cache-type-k",     "q5_1",
    "--cache-type-v",     "q5_1",
    "--flash-attn",       "on",
    "--no-context-shift",

    # Carga estricta en una sola GPU. Si no cabe, debe fallar.
    "--n-gpu-layers",     "all",
    "--fit",              "off",
    "--no-host",
    "--split-mode",       "none",
    "--main-gpu",         $GpuIndex,

    # Un solo slot recibe los 40 960 tokens completos. Los batches moderados
    # reducen picos de VRAM durante el prefill.
    "--parallel",         1,
    "--batch-size",       512,
    "--ubatch-size",      256,
    "--cont-batching",

    # No guardar slots/KV en la RAM del sistema. Se mantiene mmap porque
    # --no-mmap reserva una copia privada grande durante la carga en Windows.
    "--mmap",
    "--cache-ram",        0,
    "--no-cache-idle-slots",

    # La CPU sigue siendo necesaria para tokenizacion y HTTP, pero no ejecuta
    # capas del modelo. Estos valores minimizan su actividad y el busy-wait.
    "--threads",          1,
    "--threads-batch",    1,
    "--threads-http",     2,
    "--poll",             0,
    "--poll-batch",       0,

    # Defaults recomendados para Qwen3 en modo de pensamiento. Los clientes
    # OpenAI pueden sobrescribirlos por peticion.
    "--temp",             0.6,
    "--top-k",            20,
    "--top-p",            0.95,
    "--min-p",            0.0,

    "--host",             "0.0.0.0",
    "--port",             $Port,
    "--metrics"
)

& $LlamaBin @LlamaArgs
exit $LASTEXITCODE
