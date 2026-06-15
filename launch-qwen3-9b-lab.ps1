# launch-qwen3-9b-lab.ps1
# Variante del script de produccion para el lab:
# escucha en 0.0.0.0 para que la VM Ubuntu (NAT) pueda alcanzar el servidor.
#
# Uso: .\launch-qwen3-9b-lab.ps1 [-Context 32k|64k|128k] [-Port 8080] [-Threads 8]

param(
    [ValidateSet("32k", "64k", "128k")]
    [string]$Context = "64k",
    [int]$Port    = 8080,
    [int]$Threads = 8
)

$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\Qwen3.5-9B-Q8_0.gguf"

if (-not (Test-Path $LlamaBin))  { Write-Error "No se encuentra llama-server en: $LlamaBin"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo en: $ModelPath";   exit 1 }

switch ($Context) {
    "32k"  { $CtxSize = 32768;  $KvType = "q8_0" }
    "64k"  { $CtxSize = 65536;  $KvType = "q8_0" }
    "128k" { $CtxSize = 131072; $KvType = "q4_0" }
}

Write-Host ""
Write-Host "  [LAB] Modelo   : $ModelPath"
Write-Host "  [LAB] Contexto : $CtxSize tokens  KV: $KvType"
Write-Host "  [LAB] Host     : 0.0.0.0:$Port  (accesible desde VM)"
Write-Host ""
Write-Host "  Recuerda: abre el puerto $Port en el Firewall de Windows si no lo has hecho"
Write-Host "  New-NetFirewallRule -DisplayName 'llama-server lab' -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private"
Write-Host ""

& $LlamaBin `
    --model         $ModelPath `
    --ctx-size      $CtxSize `
    --n-gpu-layers  99 `
    --cache-type-k  $KvType `
    --cache-type-v  $KvType `
    --flash-attn    on `
    --threads       $Threads `
    --batch-size    512 `
    --ubatch-size   512 `
    --host          "0.0.0.0" `
    --port          $Port `
    --mlock `
    --metrics 
