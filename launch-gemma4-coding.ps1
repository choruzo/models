# launch-gemma4-coding.ps1 - Gemma 4 12B Coder Q6_K con llama.cpp
# Optimizado para una GPU NVIDIA de 16 GB y una unica sesion simultanea.
#
# Uso:
#   .\launch-gemma4-coding.ps1
#   .\launch-gemma4-coding.ps1 -Profile speed|balanced|long -Port 8080 -Threads 12
#   .\launch-gemma4-coding.ps1 -BuiltinTools readonly
#
# BuiltinTools controla solo las herramientas experimentales ejecutadas por
# llama-server. Las herramientas enviadas por un cliente mediante la API
# OpenAI siguen disponibles con el valor predeterminado "off".

param(
    [ValidateSet("speed", "balanced", "long")]
    [string]$Profile = "balanced",

    [ValidateRange(1, 65535)]
    [int]$Port = 8080,

    [ValidateRange(1, 256)]
    [int]$Threads = 12,

    [ValidateSet("off", "readonly", "all")]
    [string]$BuiltinTools = "off"
)

$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\gemma4-coding-Q6_K.gguf"

if (-not (Test-Path -LiteralPath $LlamaBin -PathType Leaf)) {
    Write-Error "No se encuentra llama-server en: $LlamaBin"
    exit 1
}

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    Write-Error "No se encuentra el modelo en: $ModelPath"
    exit 1
}

# El GGUF declara 262K de contexto nativo, pero estos perfiles priorizan una
# latencia y un consumo estables con los pesos Q6_K residentes en una GPU de
# 16 GB. La carga es GPU-only: si pesos, KV y buffers no caben, el servidor
# fallara en vez de mover capas silenciosamente a la RAM.
switch ($Profile) {
    "speed" {
        $CtxSize   = 16384
        $KvTypeK   = "q8_0"
        $KvTypeV   = "q8_0"
        $BatchSize = 1024
        $UBatch    = 512
        $Reasoning = "off"
    }
    "balanced" {
        $CtxSize   = 32768
        $KvTypeK   = "q8_0"
        $KvTypeV   = "q8_0"
        $BatchSize = 768
        $UBatch    = 512
        $Reasoning = "auto"
    }
    "long" {
        $CtxSize   = 65536
        $KvTypeK   = "q4_0"
        $KvTypeV   = "q4_0"
        $BatchSize = 512
        $UBatch    = 256
        $Reasoning = "auto"
    }
}

$BuiltinToolList = switch ($BuiltinTools) {
    "readonly" { "read_file,file_glob_search,grep_search,get_datetime" }
    "all"      { "all" }
    default    { $null }
}

Write-Host ""
Write-Host "  Modelo          : $ModelPath"
Write-Host "  Alias           : gemma4-coding"
Write-Host "  Perfil          : $Profile"
Write-Host "  Contexto        : $CtxSize tokens"
Write-Host "  KV cache        : $KvTypeK / $KvTypeV"
Write-Host "  Batch / UBatch  : $BatchSize / $UBatch"
Write-Host "  Reasoning       : $Reasoning"
Write-Host "  Threads         : $Threads"
Write-Host "  API             : http://127.0.0.1:$Port/v1"
Write-Host "  Built-in tools  : $BuiltinTools"
Write-Host "  GPU-only        : si (sin offload automatico a RAM)"
Write-Host ""

if ($BuiltinTools -eq "all") {
    Write-Warning "Se habilitaran herramientas con escritura y ejecucion de comandos. Usalas solo con prompts y clientes de confianza."
}

$LlamaArgs = @(
    "--model",          $ModelPath,
    "--alias",          "gemma4-coding",
    "--jinja",
    "--reasoning",      $Reasoning,
    "--ctx-size",       $CtxSize,
    "--cache-type-k",   $KvTypeK,
    "--cache-type-v",   $KvTypeV,
    "--flash-attn",     "on",
    "--batch-size",     $BatchSize,
    "--ubatch-size",    $UBatch,
    "--threads",        $Threads,
    "--threads-batch",  $Threads,
    "--n-gpu-layers",   "all",
    "--fit",            "off",
    "--no-host",
    "--parallel",       "1",
    "--cont-batching",
    "--cache-prompt",
    "--cache-reuse",    "256",
    "--host",           "0.0.0.0",
    "--port",           $Port,
    "--metrics"
)

# No se especifica --chat-template: el GGUF contiene una plantilla propia para
# pensamiento y tool calling que llama.cpp debe conservar.
if ($BuiltinToolList) {
    $LlamaArgs += @("--tools", $BuiltinToolList)
}

& $LlamaBin @LlamaArgs
exit $LASTEXITCODE
