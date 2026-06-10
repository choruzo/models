# vLLM — Servidor de inferencia para producción

vLLM es el motor de mayor rendimiento para entornos con múltiples usuarios concurrentes. Implementa *PagedAttention* y *continuous batching*, técnicas que maximizan el uso de VRAM y la capacidad de atender peticiones en paralelo.

## Requisitos

- Linux (recomendado Ubuntu 22.04+)
- Python 3.9–3.12
- NVIDIA GPU con CUDA 11.8+ y mínimo **16 GB de VRAM** (modelos 7B en FP16)
- Driver NVIDIA ≥ 525

> AMD (ROCm) está soportado de forma experimental. Apple Silicon no está soportado.

---

## Instalación

```bash
# Entorno virtual recomendado
python3 -m venv venv-vllm
source venv-vllm/bin/activate

# Instalar vLLM (selecciona la variante según tu versión de CUDA)
pip install vllm
```

Verifica la instalación:

```bash
python -c "import vllm; print(vllm.__version__)"
```

---

## Descargar un modelo

vLLM descarga automáticamente desde HuggingFace al primer arranque, pero es mejor precargarlo:

```bash
pip install huggingface-hub
huggingface-cli login   # solo necesario para modelos con gating (Llama 3, Gemma, etc.)

huggingface-cli download \
  mistralai/Mistral-7B-Instruct-v0.3 \
  --local-dir ./models/Mistral-7B-Instruct-v0.3
```

### Modelos cuantizados (menor VRAM)

Si no tienes suficiente VRAM en FP16, usa variantes cuantizadas AWQ o GPTQ:

```bash
huggingface-cli download \
  TheBloke/Mistral-7B-Instruct-v0.2-AWQ \
  --local-dir ./models/Mistral-7B-Instruct-v0.2-AWQ
```

---

## Arrancar el servidor

### Configuración básica

```bash
python -m vllm.entrypoints.openai.api_server \
  --model ./models/Mistral-7B-Instruct-v0.3 \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name mistral-7b
```

### Configuración para producción

```bash
python -m vllm.entrypoints.openai.api_server \
  --model ./models/Mistral-7B-Instruct-v0.3 \
  --host 127.0.0.1 \
  --port 8000 \
  --served-model-name mistral-7b \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --max-num-seqs 256 \
  --api-key "tu-api-key-interna"
```

### Modelo cuantizado AWQ

```bash
python -m vllm.entrypoints.openai.api_server \
  --model ./models/Mistral-7B-Instruct-v0.2-AWQ \
  --quantization awq \
  --host 127.0.0.1 \
  --port 8000 \
  --served-model-name mistral-7b-awq
```

### Parámetros importantes

| Parámetro | Descripción |
|---|---|
| `--model` | Ruta local o nombre en HuggingFace Hub |
| `--served-model-name` | Nombre que verán los clientes en `/v1/models` |
| `--host` | IP de escucha |
| `--port` | Puerto HTTP (por defecto 8000) |
| `--max-model-len` | Longitud máxima de contexto en tokens |
| `--gpu-memory-utilization` | Fracción de VRAM a reservar (0.0–1.0) |
| `--max-num-seqs` | Máximo de secuencias concurrentes en el batch |
| `--quantization` | `awq`, `gptq`, `fp8`, etc. |
| `--tensor-parallel-size` | Número de GPUs para tensor parallelism |
| `--api-key` | Clave requerida en `Authorization: Bearer` |

---

## Multi-GPU (tensor parallelism)

Para modelos grandes que no caben en una GPU:

```bash
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-3-70b-Instruct \
  --tensor-parallel-size 4 \   # 4 GPUs
  --host 127.0.0.1 \
  --port 8000
```

---

## Verificar que funciona

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer tu-api-key-interna" \
  -d '{
    "model": "mistral-7b",
    "messages": [{"role": "user", "content": "¿Cuántas GPU tienes disponibles?"}],
    "max_tokens": 100
  }'
```

```bash
# Listar modelos disponibles
curl http://localhost:8000/v1/models \
  -H "Authorization: Bearer tu-api-key-interna"
```

---

## Ejecutar como servicio systemd

```ini
# /etc/systemd/system/vllm.service
[Unit]
Description=vLLM inference server
After=network.target

[Service]
Type=simple
User=vllm
WorkingDirectory=/opt/vllm
Environment="CUDA_VISIBLE_DEVICES=0"
ExecStart=/opt/vllm/venv-vllm/bin/python -m vllm.entrypoints.openai.api_server \
    --model /opt/models/Mistral-7B-Instruct-v0.3 \
    --host 127.0.0.1 \
    --port 8000 \
    --served-model-name mistral-7b \
    --gpu-memory-utilization 0.90 \
    --api-key REEMPLAZAR_CON_TU_CLAVE
Restart=on-failure
RestartSec=10
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vllm
sudo journalctl -fu vllm
```

---

## Referencia de endpoints (API OpenAI-compatible)

| Endpoint | Descripción |
|---|---|
| `GET /v1/models` | Lista modelos disponibles |
| `POST /v1/chat/completions` | Chat con historial de mensajes |
| `POST /v1/completions` | Completion de texto libre |
| `POST /v1/embeddings` | Vectores de embeddings (si se configura) |

---

Siguiente: [Despliegue organizacional](05-organizacion.md)
