# bench-perplexity.ps1 — Benchmark de calidad (perplexity) para Qwen3.6-27B
# Compara KV q4 vs q8 vs f16 para medir perdida de precision real
# Uso: .\bench-perplexity.ps1 [-Context 32k|64k]
#
# Necesita un archivo de texto para calcular perplexity.
# Se usa wikitext-2 (estandar) o puedes apuntar a codigo fuente propio.

param(
    [ValidateSet("32k", "64k")]
    [string]$Context = "32k"
)

$BinDir       = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release"
$ModelPath    = "G:\models\Qwen3.6-27B-UD-Q3_K_XL.gguf"
$LlamaPerp    = "$BinDir\llama-perplexity.exe"
$ResultsFile  = "G:\models\perplexity-results-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"

# Archivo de texto de referencia — descarga wikitext-2 o apunta a codigo tuyo
# Para descargar: Invoke-WebRequest -Uri "https://raw.githubusercontent.com/..." -OutFile "G:\models\wikitext2.txt"
$TestFile     = "G:\models\test-corpus.txt"

if (-not (Test-Path $LlamaPerp)) { Write-Error "No se encuentra llama-perplexity en: $LlamaPerp"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo en: $ModelPath";         exit 1 }

if (-not (Test-Path $TestFile)) {
    Write-Host ""
    Write-Host "  No se encuentra el corpus de prueba: $TestFile"
    Write-Host "  Generando corpus de codigo de ejemplo (~500KB)..."
    Write-Host ""

    # Genera un corpus de codigo Python/JS sintetico si no hay uno
    $corpus = @"
# Python code corpus for perplexity testing
import os, sys, json, re, math
from typing import List, Dict, Optional, Tuple, Any
from dataclasses import dataclass, field
from pathlib import Path
from collections import defaultdict, Counter

@dataclass
class Config:
    model_path: str
    max_tokens: int = 2048
    temperature: float = 0.7
    top_p: float = 0.9
    repetition_penalty: float = 1.1
    batch_size: int = 512

def load_model(config: Config) -> Any:
    """Load a language model from disk."""
    path = Path(config.model_path)
    if not path.exists():
        raise FileNotFoundError(f"Model not found: {config.model_path}")
    return {"path": str(path), "config": config}

class TokenizerBase:
    def __init__(self, vocab_size: int = 32000):
        self.vocab_size = vocab_size
        self.token_to_id: Dict[str, int] = {}
        self.id_to_token: Dict[int, str] = {}

    def encode(self, text: str) -> List[int]:
        tokens = text.split()
        return [self.token_to_id.get(t, 0) for t in tokens]

    def decode(self, ids: List[int]) -> str:
        return " ".join(self.id_to_token.get(i, "<unk>") for i in ids)

def compute_perplexity(logits: List[float], labels: List[int]) -> float:
    total_loss = 0.0
    for i, (logit, label) in enumerate(zip(logits, labels)):
        total_loss += -math.log(max(logit, 1e-9))
    return math.exp(total_loss / max(len(labels), 1))

class AttentionBlock:
    def __init__(self, embed_dim: int, num_heads: int, dropout: float = 0.1):
        self.embed_dim = embed_dim
        self.num_heads = num_heads
        self.head_dim = embed_dim // num_heads
        self.scale = self.head_dim ** -0.5
        self.dropout = dropout

    def forward(self, x, mask=None):
        batch, seq, dim = x.shape
        q = self._project(x, "query")
        k = self._project(x, "key")
        v = self._project(x, "value")
        attn = (q @ k.transpose(-2, -1)) * self.scale
        if mask is not None:
            attn = attn.masked_fill(mask == 0, float("-inf"))
        return attn, v

def generate_tokens(model, prompt: str, config: Config) -> List[str]:
    tokens = []
    input_ids = [1] + [ord(c) % 1000 for c in prompt[:100]]
    for step in range(config.max_tokens):
        next_token = (input_ids[-1] * 31337 + step) % config.vocab_size
        tokens.append(chr(65 + next_token % 26))
        input_ids.append(next_token)
        if next_token == 2:
            break
    return tokens

# JavaScript / TypeScript patterns
const_js = """
async function fetchData(url: string, options?: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    if (!response.ok) throw new Error(`HTTP error: ${response.status}`);
    return response;
  } finally {
    clearTimeout(timeout);
  }
}

interface ModelConfig {
  modelPath: string;
  contextSize: number;
  gpuLayers: number;
  flashAttn: boolean;
  kvCacheType: 'q4_0' | 'q8_0' | 'f16';
}

class LlamaClient {
  private config: ModelConfig;
  private isLoaded: boolean = false;

  constructor(config: ModelConfig) {
    this.config = config;
  }

  async load(): Promise<void> {
    if (this.isLoaded) return;
    await this.initializeModel(this.config);
    this.isLoaded = true;
  }

  async complete(prompt: string, maxTokens: number = 256): Promise<string> {
    if (!this.isLoaded) await this.load();
    return this.generateTokens(prompt, maxTokens);
  }

  private async initializeModel(config: ModelConfig): Promise<void> {
    console.log(`Loading model: ${config.modelPath}`);
  }

  private async generateTokens(prompt: string, n: number): Promise<string> {
    return prompt.slice(0, 50) + '...';
  }
}
"""

# Rust patterns
rust_code = """
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

#[derive(Debug, Clone)]
pub struct InferenceEngine {
    model_path: String,
    context_size: usize,
    n_gpu_layers: i32,
    kv_cache_type: KvCacheType,
}

#[derive(Debug, Clone, Copy)]
pub enum KvCacheType {
    F16,
    Q8_0,
    Q4_0,
}

impl InferenceEngine {
    pub fn new(model_path: &str, context_size: usize) -> Self {
        Self {
            model_path: model_path.to_string(),
            context_size,
            n_gpu_layers: 99,
            kv_cache_type: KvCacheType::Q8_0,
        }
    }

    pub async fn generate(&self, prompt: &str, max_tokens: usize) -> Result<String, Box<dyn std::error::Error>> {
        let tokens = self.tokenize(prompt)?;
        let output = self.run_inference(&tokens, max_tokens).await?;
        Ok(self.detokenize(&output))
    }

    fn tokenize(&self, text: &str) -> Result<Vec<u32>, Box<dyn std::error::Error>> {
        Ok(text.bytes().map(|b| b as u32).collect())
    }

    async fn run_inference(&self, tokens: &[u32], max_tokens: usize) -> Result<Vec<u32>, Box<dyn std::error::Error>> {
        Ok(tokens[..max_tokens.min(tokens.len())].to_vec())
    }

    fn detokenize(&self, tokens: &[u32]) -> String {
        tokens.iter().map(|&t| char::from(t as u8)).collect()
    }
}
"""
"@
    # Repetir el corpus hasta ~500KB
    $repeated = $corpus * 20
    $repeated | Out-File $TestFile -Encoding utf8
    Write-Host "  Corpus generado: $TestFile ($([int]((Get-Item $TestFile).Length/1024)) KB)"
}

# ─── Configuraciones a comparar ───────────────────────────────────────────────
$CtxSize = if ($Context -eq "32k") { 32768 } else { 65536 }
$NGL     = if ($Context -eq "32k") { 99    } else { 30    }

$PerpConfigs = @(
    [PSCustomObject]@{ Name="kv_f16_fa";   KvK="f16";  KvV="f16";  FA=$true  }
    [PSCustomObject]@{ Name="kv_q8_fa";    KvK="q8_0"; KvV="q8_0"; FA=$true  }
    [PSCustomObject]@{ Name="kv_q4_fa";    KvK="q4_0"; KvV="q4_0"; FA=$true  }
    [PSCustomObject]@{ Name="kv_q8_nofa";  KvK="q8_0"; KvV="q8_0"; FA=$false }
    [PSCustomObject]@{ Name="kv_q4_nofa";  KvK="q4_0"; KvV="q4_0"; FA=$false }
)

Write-Host ""
Write-Host "  Contexto : $CtxSize  |  NGL: $NGL"
Write-Host "  Corpus   : $TestFile"
Write-Host ""

"Config,KvK,KvV,FlashAttn,Perplexity,Status" | Out-File $ResultsFile -Encoding utf8

foreach ($cfg in $PerpConfigs) {
    Write-Host "  $($cfg.Name) ..." -NoNewline

    $args = @(
        "--model",         $ModelPath,
        "--ctx-size",      $CtxSize,
        "--n-gpu-layers",  $NGL,
        "--cache-type-k",  $cfg.KvK,
        "--cache-type-v",  $cfg.KvV,
        "--file",          $TestFile,
        "--perplexity"
    )
    if ($cfg.FA) { $args += "--flash-attn" }

    try {
        $raw    = & $LlamaPerp @args 2>&1
        $pplLine = $raw | Where-Object { $_ -match "Perplexity" } | Select-Object -Last 1
        $ppl    = if ($pplLine -match "(\d+\.\d+)") { $Matches[1] } else { "N/A" }
        $status = "OK"
        Write-Host "  PPL = $ppl"
    }
    catch {
        $ppl = "ERR"; $status = "ERROR: $_"
        Write-Host "  ERROR"
    }

    "$($cfg.Name),$($cfg.KvK),$($cfg.KvV),$($cfg.FA),$ppl,$status" |
        Out-File $ResultsFile -Append -Encoding utf8
}

# ─── Resumen ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─── Resultados perplexity ($Context) ───────────────────────────────"
$results = Import-Csv $ResultsFile | Where-Object { $_.Status -eq "OK" }
$results | Sort-Object { [double]$_.Perplexity } |
    Format-Table Config, KvK, FlashAttn, Perplexity -AutoSize

$best = $results | Sort-Object { [double]$_.Perplexity } | Select-Object -First 1
Write-Host "  Menor perplexity (mejor calidad): $($best.Config)  PPL=$($best.Perplexity)"
Write-Host ""
Write-Host "  CSV: $ResultsFile"
