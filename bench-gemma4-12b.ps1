# bench-gemma4-12b.ps1 - Benchmark integral para Gemma 4 12B via llama.cpp
# Evalua rendimiento, calidad aproximada y resistencia de contexto.
# Uso:
#   .\bench-gemma4-12b.ps1 [-Mode quick|full] [-Context 32k|42k|64k|all] [-Port 19098]
#                           [-Threads 12] [-UseMtp] [-SkipPerplexity] [-SkipEval] [-SkipContext]

param(
    [ValidateSet("quick", "full")]
    [string]$Mode = "quick",

    [ValidateSet("32k", "42k", "64k", "all")]
    [string]$Context = "all",

    [int]$Port = 19098,

    [int]$Threads = 12,

    [switch]$UseMtp,

    [switch]$SkipPerplexity,

    [switch]$SkipEval,

    [switch]$SkipContext
)

$BinDir         = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release"
$LlamaServer    = Join-Path $BinDir "llama-server.exe"
$LlamaPerplexity = Join-Path $BinDir "llama-perplexity.exe"
$ModelPath      = "G:\models\gemma-4-12b-it-UD-Q6_K_XL.gguf"
$DraftModelPath = "G:\models\gemma-4-12b-it-Q8_0-MTP.gguf"
$Stamp          = Get-Date -Format 'yyyyMMdd-HHmmss'
$ResultsCsv     = "G:\models\bench-gemma4-12b-$Stamp.csv"
$SummaryMd      = "G:\models\bench-gemma4-12b-$Stamp.md"
$CorpusFile     = "G:\models\test-corpus-gemma.txt"

if (-not (Test-Path $LlamaServer)) { Write-Error "No se encuentra llama-server en: $LlamaServer"; exit 1 }
if (-not (Test-Path $ModelPath))   { Write-Error "No se encuentra el modelo en: $ModelPath"; exit 1 }

function Get-ContextProfiles {
    $profiles = @{
        "32k" = [PSCustomObject]@{ Name = "32k"; CtxSize = 32768; KvTypeK = "q8_0"; KvTypeV = "q8_0"; BatchSize = 768; UBatch = 512 }
        "42k" = [PSCustomObject]@{ Name = "42k"; CtxSize = 43008; KvTypeK = "q4_0"; KvTypeV = "q4_0"; BatchSize = 768; UBatch = 512 }
        "64k" = [PSCustomObject]@{ Name = "64k"; CtxSize = 65536; KvTypeK = "q4_0"; KvTypeV = "q4_0"; BatchSize = 512; UBatch = 256 }
    }

    switch ($Context) {
        "32k" { return @($profiles["32k"]) }
        "42k" { return @($profiles["42k"]) }
        "64k" { return @($profiles["64k"]) }
        default { return @($profiles["32k"], $profiles["42k"], $profiles["64k"]) }
    }
}

function Ensure-TestCorpus {
    param([string]$Path)

    if (Test-Path $Path) { return }

    $seed = @"
Gemma benchmark corpus.
This text mixes prose, structured reasoning, short algorithms, and factual descriptions.

Python function example:
def binary_search(items, target):
    left, right = 0, len(items) - 1
    while left <= right:
        mid = (left + right) // 2
        if items[mid] == target:
            return mid
        if items[mid] < target:
            left = mid + 1
        else:
            right = mid - 1
    return -1

Checklist:
1. Validate inputs.
2. Measure latency.
3. Compare output consistency.
4. Track context retention.

The quick brown fox jumps over the lazy dog.
Large language models can trade memory for longer context and may lose accuracy under aggressive cache quantization.
"@

    (($seed + [Environment]::NewLine) * 800) | Out-File $Path -Encoding utf8
}

function Wait-ServerReady {
    param([int]$Port, [int]$MaxWaitSec = 180)

    $url = "http://127.0.0.1:$Port/health"
    $deadline = (Get-Date).AddSeconds($MaxWaitSec)

    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-RestMethod -Uri $url -TimeoutSec 3 -ErrorAction Stop
            if ($resp.status -eq "ok") { return $true }
        }
        catch {}
        Start-Sleep -Seconds 2
    }

    return $false
}

function Stop-Server {
    param([System.Diagnostics.Process]$Proc)

    if ($Proc -and -not $Proc.HasExited) {
        $Proc.Kill()
        $Proc.WaitForExit(5000) | Out-Null
    }

    Get-Process "llama-server" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Invoke-Completion {
    param(
        [int]$Port,
        [string]$Prompt,
        [int]$NPredict = 128,
        [double]$Temperature = 0.0,
        [bool]$CachePrompt = $false
    )

    $body = @{
        prompt       = $Prompt
        n_predict    = $NPredict
        temperature  = $Temperature
        cache_prompt = $CachePrompt
    } | ConvertTo-Json -Depth 4

    return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/completion" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 600
}

function Normalize-ModelText {
    param([string]$Text)

    if ($null -eq $Text) { return "" }

    $clean = $Text
    $clean = $clean -replace '<\|channel\|>', ' '
    $clean = $clean -replace '<\|[^>]+\|>', ' '
    $clean = $clean -replace '```(?:json|text)?', ' '
    $clean = $clean -replace '[\r\n]+', ' '
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim()
}

function Get-ThroughputPrompts {
    $short = "Explain in plain Spanish what a binary search does and provide a Python example with type hints."
    $mediumBase = "Write a concise technical note comparing hash tables and binary search trees, include complexity and one implementation caveat. "
    $longBase = "Design a small task runner in Python with queue management, retries, logging, and unit tests. Explain the architecture decisions. "

    $medium = ($mediumBase * 10).Substring(0, 900)
    $long = ($longBase * 30).Substring(0, 3600)

    if ($Mode -eq "quick") {
        return @(
            @{ Name = "pp_short"; Text = $short },
            @{ Name = "pp_medium"; Text = $medium }
        )
    }

    return @(
        @{ Name = "pp_short"; Text = $short },
        @{ Name = "pp_medium"; Text = $medium },
        @{ Name = "pp_long"; Text = $long }
    )
}

function Measure-Throughput {
    param([int]$Port)

    $prompts = Get-ThroughputPrompts
    $nPredict = if ($Mode -eq "quick") { 96 } else { 160 }
    $results = @()

    foreach ($prompt in $prompts) {
        try {
            $resp = Invoke-Completion -Port $Port -Prompt $prompt.Text -NPredict $nPredict
            $timings = $resp.timings
            $ppTs = if ($timings.prompt_ms -gt 0) { [math]::Round($timings.prompt_n / ($timings.prompt_ms / 1000), 1) } else { 0 }
            $tgTs = if ($timings.predicted_ms -gt 0) { [math]::Round($timings.predicted_n / ($timings.predicted_ms / 1000), 1) } else { 0 }

            $results += [PSCustomObject]@{
                Area = "throughput"
                Case = $prompt.Name
                Metric1 = $ppTs
                Metric2 = $tgTs
                Status = "OK"
                Notes = "prompt_toks=$($timings.prompt_n);pred_toks=$($timings.predicted_n)"
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Area = "throughput"
                Case = $prompt.Name
                Metric1 = 0
                Metric2 = 0
                Status = "ERROR"
                Notes = $_.Exception.Message
            }
        }
    }

    return $results
}

function Get-EvalCases {
    $jsonPrompt = @"
Responde solo con JSON valido con las claves exactas answer y confidence.
Question: What is 37 + 58?
Expected behavior: answer must be 95.
"@

    $instructionPrompt = @"
Sigue exactamente estas instrucciones:
1. Responde en una sola linea.
2. Incluye la palabra CLAVE al inicio.
3. Resume en menos de 12 palabras que hace una pila stack.
"@

    $coherencePrompt = @"
Escribe exactamente tres frases cortas sobre por que las pruebas automatizadas reducen regresiones.
No uses listas.
"@

    return @(
        [PSCustomObject]@{ Name = "math_exact"; Prompt = $jsonPrompt; Expect = "95"; Type = "contains" },
        [PSCustomObject]@{ Name = "instruction_following"; Prompt = $instructionPrompt; Expect = "CLAVE"; Type = "prefix" },
        [PSCustomObject]@{ Name = "coherence_three_sentences"; Prompt = $coherencePrompt; Expect = "3"; Type = "sentence_count" }
    )
}

function Test-EvalCases {
    param([int]$Port)

    $results = @()

    foreach ($case in (Get-EvalCases)) {
        try {
            $resp = Invoke-Completion -Port $Port -Prompt $case.Prompt -NPredict 120 -Temperature 0.0
            $text = [string]$resp.content
            $normalized = Normalize-ModelText -Text $text
            $score = 0
            $notes = ""

            switch ($case.Type) {
                "contains" {
                    $score = if ($normalized -match [regex]::Escape($case.Expect)) { 1 } else { 0 }
                    $notes = $normalized
                }
                "prefix" {
                    $score = if ($normalized.StartsWith($case.Expect)) { 1 } else { 0 }
                    $notes = $normalized
                }
                "sentence_count" {
                    $sentences = ([regex]::Matches($normalized, "[\.!?](\s|$)")).Count
                    $score = if ($sentences -eq 3) { 1 } else { 0 }
                    $notes = "sentences=$sentences; text=$normalized"
                }
            }

            $results += [PSCustomObject]@{
                Area = "eval"
                Case = $case.Name
                Metric1 = $score
                Metric2 = 1
                Status = "OK"
                Notes = $notes
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Area = "eval"
                Case = $case.Name
                Metric1 = 0
                Metric2 = 1
                Status = "ERROR"
                Notes = $_.Exception.Message
            }
        }
    }

    return $results
}

function New-ContextPrompt {
    param([string]$Needle)

    $facts = @(
        "Alpha code = RIO-17",
        "Beta city = Seville",
        "Gamma checksum = 48291",
        "Delta owner = Marta",
        "Target token = $Needle",
        "Omega window = 14"
    )

    $paddingBlock = @"
Context notes on systems design, storage tiers, caching trade-offs, observability, rollback plans and deployment safety.
Do not summarize these notes. Keep reading until the end and then follow the final instruction.
"@
    $padding = (($paddingBlock + [Environment]::NewLine) * 180)

    return @"
Memorize the facts below because you will need one of them at the end.

$($facts -join [Environment]::NewLine)

$padding
Final instruction: reply with only the exact value of Target token. No explanation.
"@
}

function Test-ContextRetention {
    param([int]$Port, [int]$CtxSize)

    $token = if ($CtxSize -ge 65536) { "CTX64-OK" } elseif ($CtxSize -ge 43008) { "CTX42-OK" } else { "CTX32-OK" }
    $prompt = New-ContextPrompt -Needle $token

    try {
        $resp = Invoke-Completion -Port $Port -Prompt $prompt -NPredict 24 -Temperature 0.0
        $text = [string]$resp.content
        $normalized = Normalize-ModelText -Text $text
        $score = if ($normalized -match [regex]::Escape($token)) { 1 } else { 0 }

        return [PSCustomObject]@{
            Area = "context"
            Case = "retention"
            Metric1 = $score
            Metric2 = 1
            Status = "OK"
            Notes = $normalized
        }
    }
    catch {
        return [PSCustomObject]@{
            Area = "context"
            Case = "retention"
            Metric1 = 0
            Metric2 = 1
            Status = "ERROR"
            Notes = $_.Exception.Message
        }
    }
}

function Measure-Perplexity {
    param($Profile)

    if (-not (Test-Path $LlamaPerplexity)) {
        return [PSCustomObject]@{
            Area = "perplexity"
            Case = $Profile.Name
            Metric1 = -1
            Metric2 = 0
            Status = "SKIPPED"
            Notes = "No se encuentra llama-perplexity.exe"
        }
    }

    Ensure-TestCorpus -Path $CorpusFile

    $args = @(
        "--model",         $ModelPath,
        "--ctx-size",      $Profile.CtxSize,
        "--n-gpu-layers",  "all",
        "--cache-type-k",  $Profile.KvTypeK,
        "--cache-type-v",  $Profile.KvTypeV,
        "--file",          $CorpusFile,
        "--perplexity"
    )

    try {
        $raw = & $LlamaPerplexity @args 2>&1
        $pplLine = $raw | Where-Object { $_ -match "Perplexity" } | Select-Object -Last 1
        $ppl = if ($pplLine -match "(\d+\.\d+)") { [double]$Matches[1] } else { -1 }

        return [PSCustomObject]@{
            Area = "perplexity"
            Case = $Profile.Name
            Metric1 = $ppl
            Metric2 = 0
            Status = if ($ppl -ge 0) { "OK" } else { "ERROR" }
            Notes = if ($pplLine) { $pplLine.Trim() } else { "No se pudo parsear la salida" }
        }
    }
    catch {
        return [PSCustomObject]@{
            Area = "perplexity"
            Case = $Profile.Name
            Metric1 = -1
            Metric2 = 0
            Status = "ERROR"
            Notes = $_.Exception.Message
        }
    }
}

function Start-ProfileServer {
    param($Profile)

    $useDraft = $UseMtp.IsPresent -and (Test-Path $DraftModelPath)

    $args = @(
        "--model",           $ModelPath,
        "--alias",           "gemma-4-12b",
        "--chat-template",   "gemma",
        "--jinja",
        "--reasoning",       "auto",
        "--ctx-size",        $Profile.CtxSize,
        "--cache-type-k",    $Profile.KvTypeK,
        "--cache-type-v",    $Profile.KvTypeV,
        "--flash-attn",      "on",
        "--batch-size",      $Profile.BatchSize,
        "--ubatch-size",     $Profile.UBatch,
        "--threads",         $Threads,
        "--threads-batch",   $Threads,
        "--n-gpu-layers",    "all",
        "--fit",             "on",
        "--fit-target",      "1536",
        "--parallel",        "1",
        "--cont-batching",
        "--kv-unified",
        "--cache-prompt",
        "--host",            "127.0.0.1",
        "--port",            $Port,
        "--metrics",
        "--mlock"
    )

    if ($useDraft) {
        $args += @(
            "--model-draft",        $DraftModelPath,
            "--spec-type",          "draft-mtp",
            "--spec-draft-n-max",   "4",
            "--spec-draft-n-min",   "1",
            "--n-gpu-layers-draft", "all"
        )
    }

    $errFile = Join-Path $env:TEMP "llama-gemma-bench-$($Profile.Name)-err.txt"
    return Start-Process -FilePath $LlamaServer -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardError $errFile
}

$profiles = Get-ContextProfiles

"Profile,Area,Case,Metric1,Metric2,Status,Notes" | Out-File $ResultsCsv -Encoding utf8

$summaryLines = @(
    "# Benchmark Gemma 4 12B",
    "",
    "- Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Modelo: $ModelPath",
    "- Modo: $Mode",
    "- Contextos: $($profiles.Name -join ', ')",
    "- MTP: $($UseMtp.IsPresent)",
    ""
)

Write-Host ""
Write-Host "  Modelo   : $ModelPath"
Write-Host "  Modo     : $Mode"
Write-Host "  Perfiles : $($profiles.Name -join ', ')"
Write-Host "  Salida   : $ResultsCsv"
Write-Host "  Resumen  : $SummaryMd"
Write-Host ""

foreach ($profile in $profiles) {
    Write-Host "== Perfil $($profile.Name) ($($profile.CtxSize) tokens) ==" -ForegroundColor Cyan

    $proc = $null
    try {
        $proc = Start-ProfileServer -Profile $profile
        Write-Host "  Esperando servidor..." -NoNewline
        if (-not (Wait-ServerReady -Port $Port)) {
            Write-Host " TIMEOUT" -ForegroundColor Red
            "$($profile.Name),startup,ready,0,0,TIMEOUT,No responde /health" | Out-File $ResultsCsv -Append -Encoding utf8
            $summaryLines += "- $($profile.Name): TIMEOUT al iniciar servidor"
            continue
        }
        Write-Host " OK" -ForegroundColor Green

        try {
            Invoke-Completion -Port $Port -Prompt "Warmup" -NPredict 8 | Out-Null
        }
        catch {}

        $profileResults = @()
        $profileResults += Measure-Throughput -Port $Port
        if (-not $SkipEval) { $profileResults += Test-EvalCases -Port $Port }
        if (-not $SkipContext) { $profileResults += Test-ContextRetention -Port $Port -CtxSize $profile.CtxSize }

        foreach ($row in $profileResults) {
            "$($profile.Name),$($row.Area),$($row.Case),$($row.Metric1),$($row.Metric2),$($row.Status),$($row.Notes.Replace(',', ';'))" |
                Out-File $ResultsCsv -Append -Encoding utf8
        }

        if (-not $SkipPerplexity) {
            $ppl = Measure-Perplexity -Profile $profile
            "$($profile.Name),$($ppl.Area),$($ppl.Case),$($ppl.Metric1),$($ppl.Metric2),$($ppl.Status),$($ppl.Notes.Replace(',', ';'))" |
                Out-File $ResultsCsv -Append -Encoding utf8
            $profileResults += $ppl
        }

        $avgPP = ($profileResults | Where-Object { $_.Area -eq "throughput" } | Measure-Object Metric1 -Average).Average
        $avgTG = ($profileResults | Where-Object { $_.Area -eq "throughput" } | Measure-Object Metric2 -Average).Average
        $evalScore = ($profileResults | Where-Object { $_.Area -eq "eval" } | Measure-Object Metric1 -Average).Average
        $contextScore = ($profileResults | Where-Object { $_.Area -eq "context" } | Measure-Object Metric1 -Average).Average
        $pplScore = ($profileResults | Where-Object { $_.Area -eq "perplexity" } | Select-Object -First 1).Metric1

        $summaryLines += "## $($profile.Name)"
        $summaryLines += ""
        $summaryLines += "- Prompt processing medio: $([math]::Round(($avgPP | ForEach-Object { if ($_ -ne $null) { $_ } else { 0 } }), 1)) t/s"
        $summaryLines += "- Generacion media: $([math]::Round(($avgTG | ForEach-Object { if ($_ -ne $null) { $_ } else { 0 } }), 1)) t/s"
        if (-not $SkipEval) { $summaryLines += "- Precision/coherencia: $([math]::Round(($evalScore | ForEach-Object { if ($_ -ne $null) { $_ * 100 } else { 0 } }), 0))%" }
        if (-not $SkipContext) { $summaryLines += "- Retencion de contexto: $([math]::Round(($contextScore | ForEach-Object { if ($_ -ne $null) { $_ * 100 } else { 0 } }), 0))%" }
        if (-not $SkipPerplexity) { $summaryLines += "- Perplexity: $pplScore" }
        $summaryLines += ""

        Write-Host "  PP medio : $([math]::Round(($avgPP | ForEach-Object { if ($_ -ne $null) { $_ } else { 0 } }), 1)) t/s"
        Write-Host "  TG media : $([math]::Round(($avgTG | ForEach-Object { if ($_ -ne $null) { $_ } else { 0 } }), 1)) t/s"
        if (-not $SkipEval) { Write-Host "  Eval     : $([math]::Round(($evalScore | ForEach-Object { if ($_ -ne $null) { $_ * 100 } else { 0 } }), 0))%" }
        if (-not $SkipContext) { Write-Host "  Contexto : $([math]::Round(($contextScore | ForEach-Object { if ($_ -ne $null) { $_ * 100 } else { 0 } }), 0))%" }
        if (-not $SkipPerplexity) { Write-Host "  PPL      : $pplScore" }
    }
    finally {
        Stop-Server -Proc $proc
    }
}

$summaryLines | Out-File $SummaryMd -Encoding utf8

Write-Host ""
Write-Host "Benchmark completado." -ForegroundColor Green
Write-Host "CSV : $ResultsCsv"
Write-Host "MD  : $SummaryMd"