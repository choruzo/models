# bench-qwen.ps1 — Benchmark via llama-server API (llama-bench no disponible)
# Mide PP t/s y TG t/s para distintas configuraciones de 32K y 64K
# Uso: .\bench-qwen.ps1 [-Context 32k|64k|all] [-Quick]

param(
    [ValidateSet("32k", "64k", "all")]
    [string]$Context = "all",
    [switch]$Quick
)

$LlamaServer = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath   = "G:\models\Qwen3.6-27B-UD-Q3_K_XL.gguf"
$BenchPort   = 19099
$ResultsFile = "G:\models\bench-results-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"

if (-not (Test-Path $LlamaServer)) { Write-Error "No se encuentra: $LlamaServer"; exit 1 }
if (-not (Test-Path $ModelPath))   { Write-Error "No se encuentra: $ModelPath";   exit 1 }

# ─── Prompts de prueba (simula uso real de asistente de codigo) ───────────────
# Prompt corto ~128 tokens, medio ~512, largo ~2048
$ShortPrompt = "Write a Python function that implements binary search on a sorted list and returns the index of the target element, or -1 if not found. Include type hints and a docstring."
$MedPrompt   = ($ShortPrompt + " Also implement unit tests using pytest. " + ("Consider edge cases such as empty lists, single elements, and duplicate values. " * 8)).Substring(0, 900)
$LongPrompt  = ($ShortPrompt + " " + ("Implement a complete data structures library in Python including linked list, binary search tree, heap, hash table, and graph with BFS and DFS. Add comprehensive docstrings, type hints, and pytest unit tests for each structure. " * 12)).Substring(0, 3600)

$Prompts = if ($Quick) {
    @( @{Name="pp_short"; Text=$ShortPrompt}, @{Name="pp_medium"; Text=$MedPrompt} )
} else {
    @( @{Name="pp_short"; Text=$ShortPrompt}, @{Name="pp_medium"; Text=$MedPrompt}, @{Name="pp_long"; Text=$LongPrompt} )
}
$NPredict = if ($Quick) { 64 } else { 128 }

# ─── Configuraciones ──────────────────────────────────────────────────────────
$Configs32k = @(
    [PSCustomObject]@{ Name="32k_base";      Ctx=32768; NGL=99; KvK="q8_0"; KvV="q8_0"; FA=$false; B=512;  UB=512  }
    [PSCustomObject]@{ Name="32k_fa";        Ctx=32768; NGL=99; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=512;  UB=512  }
    [PSCustomObject]@{ Name="32k_kv_q4";     Ctx=32768; NGL=99; KvK="q4_0"; KvV="q4_0"; FA=$true;  B=512;  UB=512  }
    [PSCustomObject]@{ Name="32k_kv_f16";    Ctx=32768; NGL=99; KvK="f16";  KvV="f16";  FA=$true;  B=512;  UB=512  }
    [PSCustomObject]@{ Name="32k_b1024";     Ctx=32768; NGL=99; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=1024; UB=512  }
    [PSCustomObject]@{ Name="32k_b2048";     Ctx=32768; NGL=99; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=2048; UB=512  }
    [PSCustomObject]@{ Name="32k_ub1024";    Ctx=32768; NGL=99; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=2048; UB=1024 }
)

$Configs64k = @(
    [PSCustomObject]@{ Name="64k_ngl30_q8";  Ctx=65536; NGL=30; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=512;  UB=512  }
    [PSCustomObject]@{ Name="64k_ngl33_q8";  Ctx=65536; NGL=33; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=512;  UB=512  }
    [PSCustomObject]@{ Name="64k_ngl35_q4";  Ctx=65536; NGL=35; KvK="q4_0"; KvV="q4_0"; FA=$true;  B=512;  UB=512  }
    [PSCustomObject]@{ Name="64k_ngl99_q4";  Ctx=65536; NGL=99; KvK="q4_0"; KvV="q4_0"; FA=$true;  B=512;  UB=512  }
    [PSCustomObject]@{ Name="64k_b1024";     Ctx=65536; NGL=30; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=1024; UB=512  }
    [PSCustomObject]@{ Name="64k_b2048";     Ctx=65536; NGL=30; KvK="q8_0"; KvV="q8_0"; FA=$true;  B=2048; UB=1024 }
)

if ($Quick) {
    $Configs32k = $Configs32k | Where-Object { $_.Name -in @("32k_base","32k_fa","32k_kv_q4","32k_kv_f16") }
    $Configs64k = $Configs64k | Where-Object { $_.Name -in @("64k_ngl30_q8","64k_ngl35_q4","64k_ngl99_q4") }
}

$AllConfigs = switch ($Context) {
    "32k" { $Configs32k }
    "64k" { $Configs64k }
    "all" { $Configs32k + $Configs64k }
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
function Wait-ServerReady {
    param([int]$Port, [int]$MaxWaitSec = 120)
    $url = "http://127.0.0.1:$Port/health"
    $deadline = (Get-Date).AddSeconds($MaxWaitSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-RestMethod -Uri $url -TimeoutSec 3 -ErrorAction Stop
            if ($r.status -eq "ok") { return $true }
        } catch {}
        Start-Sleep 2
    }
    return $false
}

function Stop-ServerAndWaitVram {
    param([System.Diagnostics.Process]$Proc, [int]$MaxWaitSec = 30)

    # Matar proceso
    if ($Proc -and -not $Proc.HasExited) {
        $Proc.Kill()
        $Proc.WaitForExit(5000) | Out-Null
    }
    # Fallback: matar cualquier llama-server restante
    Get-Process "llama-server" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Esperar a que nvidia-smi reporte VRAM usada < 500 MB (modelo descargado)
    $deadline = (Get-Date).AddSeconds($MaxWaitSec)
    Write-Host "  Liberando VRAM..." -NoNewline
    while ((Get-Date) -lt $deadline) {
        try {
            $usedMiB = (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null) -as [int]
            if ($usedMiB -ne $null -and $usedMiB -lt 500) { break }
        } catch {}
        Start-Sleep 2
        Write-Host "." -NoNewline
    }
    Write-Host " listo ($([int]((Get-Date).Subtract($deadline.AddSeconds(-$MaxWaitSec)).TotalSeconds))s)"
    Start-Sleep 1
}

function Measure-Config {
    param($Cfg, $Port)
    $results = @()

    foreach ($prompt in $Prompts) {
        $body = @{
            prompt      = $prompt.Text
            n_predict   = $NPredict
            cache_prompt = $false
            temperature  = 0.0
        } | ConvertTo-Json

        try {
            $resp = Invoke-RestMethod `
                -Uri "http://127.0.0.1:$Port/completion" `
                -Method Post `
                -Body $body `
                -ContentType "application/json" `
                -TimeoutSec 300

            $t = $resp.timings
            $ppTs = if ($t.prompt_ms   -gt 0) { [math]::Round($t.prompt_n   / ($t.prompt_ms   / 1000), 1) } else { 0 }
            $tgTs = if ($t.predicted_ms -gt 0) { [math]::Round($t.predicted_n / ($t.predicted_ms / 1000), 1) } else { 0 }

            $results += [PSCustomObject]@{
                PromptName  = $prompt.Name
                PromptToks  = $t.prompt_n
                PredToks    = $t.predicted_n
                PP_ts       = $ppTs
                TG_ts       = $tgTs
            }
        } catch {
            $results += [PSCustomObject]@{
                PromptName = $prompt.Name; PromptToks = 0; PredToks = 0; PP_ts = 0; TG_ts = 0
            }
        }
    }
    return $results
}

# ─── Cabecera CSV ─────────────────────────────────────────────────────────────
"Config,Ctx,NGL,KvK,KvV,FA,Batch,UBatch,Prompt,PromptToks,PP_ts,TG_ts,Status" | Out-File $ResultsFile -Encoding utf8

Write-Host ""
Write-Host "  Modelo : $ModelPath"
Write-Host "  Configs: $($AllConfigs.Count) | Prompts por config: $($Prompts.Count)"
Write-Host "  Salida : $ResultsFile"
Write-Host ""

$Total = $AllConfigs.Count
$i = 0
$Summary = @()

foreach ($cfg in $AllConfigs) {
    $i++
    Write-Host "[$i/$Total] $($cfg.Name)" -ForegroundColor Cyan

    # Arrancar servidor con esta configuracion
    $serverArgs = @(
        "--model",         $ModelPath,
        "--ctx-size",      $cfg.Ctx,
        "--n-gpu-layers",  $cfg.NGL,
        "--cache-type-k",  $cfg.KvK,
        "--cache-type-v",  $cfg.KvV,
        "--batch-size",    $cfg.B,
        "--ubatch-size",   $cfg.UB,
        "--parallel",      "1",
        "--port",          $BenchPort,
        "--host",          "127.0.0.1"
    )
    if ($cfg.FA) { $serverArgs += @("--flash-attn", "on") }

    $proc = Start-Process -FilePath $LlamaServer -ArgumentList $serverArgs `
        -PassThru -WindowStyle Hidden -RedirectStandardError "$env:TEMP\llama-bench-err.txt"

    Write-Host "  Esperando servidor..." -NoNewline
    $ready = Wait-ServerReady -Port $BenchPort
    if (-not $ready) {
        Write-Host " TIMEOUT" -ForegroundColor Red
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        "$($cfg.Name),$($cfg.Ctx),$($cfg.NGL),$($cfg.KvK),$($cfg.KvV),$($cfg.FA),$($cfg.B),$($cfg.UB),-,-,-,-,TIMEOUT" |
            Out-File $ResultsFile -Append -Encoding utf8
        continue
    }
    Write-Host " OK" -ForegroundColor Green

    # Warmup
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$BenchPort/completion" -Method Post `
            -Body (@{prompt="Hello"; n_predict=8; temperature=0.0} | ConvertTo-Json) `
            -ContentType "application/json" -TimeoutSec 60 | Out-Null
    } catch {}

    # Mediciones
    $measures = Measure-Config -Cfg $cfg -Port $BenchPort
    $avgPP = [math]::Round(($measures | Measure-Object PP_ts -Average).Average, 1)
    $avgTG = [math]::Round(($measures | Measure-Object TG_ts -Average).Average, 1)

    Write-Host ("  " + ($measures | ForEach-Object { "$($_.PromptName): PP=$($_.PP_ts) TG=$($_.TG_ts)" } | Join-String " | "))
    Write-Host "  Media: PP=$avgPP t/s  TG=$avgTG t/s" -ForegroundColor Yellow

    foreach ($m in $measures) {
        "$($cfg.Name),$($cfg.Ctx),$($cfg.NGL),$($cfg.KvK),$($cfg.KvV),$($cfg.FA),$($cfg.B),$($cfg.UB),$($m.PromptName),$($m.PromptToks),$($m.PP_ts),$($m.TG_ts),OK" |
            Out-File $ResultsFile -Append -Encoding utf8
    }

    $Summary += [PSCustomObject]@{
        Config = $cfg.Name; Ctx = $cfg.Ctx; NGL = $cfg.NGL
        KvK = $cfg.KvK; FA = $cfg.FA; Batch = $cfg.B
        AvgPP = $avgPP; AvgTG = $avgTG
    }

    Stop-ServerAndWaitVram -Proc $proc
}

# ─── Resumen final ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══ RESULTADOS FINALES ════════════════════════════════════════════" -ForegroundColor Cyan

foreach ($ctxGroup in @(32768, 65536)) {
    $label = if ($ctxGroup -eq 32768) { "32K" } else { "64K" }
    $group = $Summary | Where-Object { $_.Ctx -eq $ctxGroup }
    if (-not $group) { continue }

    $bestTG = $group | Sort-Object AvgTG -Descending | Select-Object -First 1
    $bestPP = $group | Sort-Object AvgPP -Descending | Select-Object -First 1

    Write-Host ""
    Write-Host "  ── $label contexto ──" -ForegroundColor Yellow
    Write-Host "  Mejor TG (generacion) : $($bestTG.Config)  → $($bestTG.AvgTG) t/s"
    Write-Host "  Mejor PP (prompt proc): $($bestPP.Config)  → $($bestPP.AvgPP) t/s"
    Write-Host ""
    $group | Sort-Object AvgTG -Descending |
        Format-Table Config, NGL, KvK, FA, Batch, AvgPP, AvgTG -AutoSize
}

Write-Host "  CSV completo: $ResultsFile"
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
