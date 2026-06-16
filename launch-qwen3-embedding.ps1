# launch-qwen3-embedding.ps1
# Lanzador de Qwen3-Embedding-0.6B-f16 con llama.cpp
#
# Uso:
#   .\launch-qwen3-embedding.ps1 [-Port 8081] [-Threads 8] [-BindHost 0.0.0.0]

param(
    [int]$Port = 8081,
    [int]$Threads = 8,
    [string]$BindHost = "0.0.0.0"
)

# Rutas
$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\Qwen3-Embedding-0.6B-f16.gguf"

if (-not (Test-Path $LlamaBin))  { Write-Error "No se encuentra llama-server en: $LlamaBin"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo en: $ModelPath"; exit 1 }

Write-Host ""
Write-Host "  Modelo  : $ModelPath"
Write-Host "  Host    : $BindHost"
Write-Host "  Puerto  : $Port"
Write-Host "  Threads : $Threads"
Write-Host ""
Write-Host "Prueba rapida (embeddings):"
Write-Host "  curl http://${BindHost}:$Port/v1/embeddings -H `"Content-Type: application/json`" -d '{`"input`": `"texto de prueba`"}'"
Write-Host ""

& $LlamaBin `
    --model         $ModelPath `
    --embedding `
    --ctx-size      8192 `
    --n-gpu-layers  99 `
    --threads       $Threads `
    --host          $BindHost `
    --port          $Port `
    --mlock `
    --metrics
