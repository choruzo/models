# launch-qwen3-chat-embed-one-port.ps1
# Lanza Qwen chat + Qwen embeddings sin LiteLLM local.
#
# Uso:
#   .\launch-qwen3-chat-embed-one-port.ps1 [-Context 64k] [-Threads 8]
#
# Endpoints:
#   Chat       -> POST http://0.0.0.0:<ChatInternalPort>/v1/chat/completions
#   Embeddings -> POST http://0.0.0.0:<EmbedInternalPort>/v1/embeddings

param(
    [ValidateSet("32k", "64k", "128k")]
    [string]$Context = "64k",

    [int]$Threads = 8,

    [int]$ChatInternalPort = 8080,
    [int]$EmbedInternalPort = 8081
)

# Rutas
$LlamaBin       = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ChatModelPath  = "G:\models\Qwen3.5-9B-Q8_0.gguf"
$EmbedModelPath = "G:\models\Qwen3-Embedding-0.6B-f16.gguf"

if (-not (Test-Path $LlamaBin))       { Write-Error "No se encuentra llama-server en: $LlamaBin"; exit 1 }
if (-not (Test-Path $ChatModelPath))  { Write-Error "No se encuentra modelo chat en: $ChatModelPath"; exit 1 }
if (-not (Test-Path $EmbedModelPath)) { Write-Error "No se encuentra modelo embeddings en: $EmbedModelPath"; exit 1 }
if ($ChatInternalPort -eq $EmbedInternalPort) { Write-Error "ChatInternalPort y EmbedInternalPort deben ser distintos"; exit 1 }

switch ($Context) {
    "32k"  { $CtxSize = 32768;  $KvType = "q8_0" }
    "64k"  { $CtxSize = 65536;  $KvType = "q8_0" }
    "128k" { $CtxSize = 131072; $KvType = "q4_0" }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir    = Join-Path $env:TEMP ("qwen-chat-embed-" + $timestamp)
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$chatLog   = Join-Path $runDir "chat.log"
$embedLog  = Join-Path $runDir "embed.log"
$chatErrLog  = Join-Path $runDir "chat.err.log"
$embedErrLog = Join-Path $runDir "embed.err.log"

$chatArgs = @(
    "--model",         $ChatModelPath,
    "--ctx-size",      $CtxSize,
    "--n-gpu-layers",  99,
    "--cache-type-k",  $KvType,
    "--cache-type-v",  $KvType,
    "--flash-attn",    "on",
    "--threads",       $Threads,
    "--batch-size",    512,
    "--ubatch-size",   512,
    "--host",          "0.0.0.0",
    "--port",          $ChatInternalPort,
    "--mlock",
    "--metrics"
)

$embedArgs = @(
    "--model",         $EmbedModelPath,
    "--embedding",
    "--ctx-size",      8192,
    "--n-gpu-layers",  99,
    "--threads",       $Threads,
    "--host",          "0.0.0.0",
    "--port",          $EmbedInternalPort,
    "--mlock",
    "--metrics"
)

Write-Host ""
Write-Host "  Chat model      : $ChatModelPath"
Write-Host "  Embedding model : $EmbedModelPath"
Write-Host "  Chat endpoint   : 0.0.0.0:$ChatInternalPort"
Write-Host "  Embed endpoint  : 0.0.0.0:$EmbedInternalPort"
Write-Host "  Logs            : $runDir"
Write-Host ""

$chatProc = Start-Process -FilePath $LlamaBin -ArgumentList $chatArgs -RedirectStandardOutput $chatLog -RedirectStandardError $chatErrLog -PassThru
$embedProc = Start-Process -FilePath $LlamaBin -ArgumentList $embedArgs -RedirectStandardOutput $embedLog -RedirectStandardError $embedErrLog -PassThru

if (($null -eq $chatProc) -or ($null -eq $embedProc)) {
    Write-Error "No se pudieron iniciar uno o ambos procesos llama-server. Revisa los logs en: $runDir"
    exit 1
}

Write-Host "Proceso chat PID : $($chatProc.Id)"
Write-Host "Proceso embed PID: $($embedProc.Id)"
Write-Host ""
$chatCurl = "  curl http://0.0.0.0:$ChatInternalPort/v1/chat/completions -H `"Content-Type: application/json`" -d '{`"messages`": [{`"role`": `"user`", `"content`": `"hola`"}]}'"
$embedCurl = "  curl http://0.0.0.0:$EmbedInternalPort/v1/embeddings -H `"Content-Type: application/json`" -d '{`"input`": `"texto de prueba`"}'"

Write-Host "Prueba rapida (chat):"
Write-Host $chatCurl
Write-Host ""
Write-Host "Prueba rapida (embeddings):"
Write-Host $embedCurl
Write-Host ""
Write-Host "Pulsa Ctrl+C para detener todo."

try {
    Wait-Process -Id $chatProc.Id, $embedProc.Id -Any
}
finally {
    foreach ($p in @($chatProc, $embedProc)) {
        if ($null -ne $p) {
            try {
                if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
            }
            catch {
            }
        }
    }
}
