# llama.cpp — Servidor de inferencia ligero

llama.cpp incluye `llama-server`, un servidor HTTP que expone una API compatible con OpenAI. No requiere Python ni GPU para funcionar.

## Requisitos

- Linux / Windows / macOS
- CPU con AVX2 (cualquier x86-64 moderno)
- RAM suficiente para el modelo elegido (ver tabla de cuantizaciones en [conceptos](01-conceptos.md))
- **Opcional**: GPU NVIDIA con CUDA 11.8+ para aceleración

---

## Instalación

### Opción A — Binarios precompilados (más rápido)

Descarga el binario correspondiente a tu plataforma desde [GitHub Releases](https://github.com/ggerganov/llama.cpp/releases):

```bash
# Linux, CPU-only
wget https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-b{VERSION}-bin-ubuntu-x64.zip
unzip llama-b{VERSION}-bin-ubuntu-x64.zip -d llama-cpp
```

### Opción B — Compilar desde fuente

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

# CPU-only
cmake -B build
cmake --build build --config Release -j$(nproc)

# Con CUDA (NVIDIA)
cmake -B build -DGGML_CUDA=ON
cmake --build build --config Release -j$(nproc)
```

Los binarios quedan en `build/bin/`.

---

## Descargar un modelo GGUF

```bash
pip install huggingface-hub --break-system-packages

# Ejemplo: Mistral 7B Q4_K_M
huggingface-cli download \
  bartowski/Mistral-7B-Instruct-v0.3-GGUF \
  Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --local-dir ./models
```

---

## Arrancar llama-server

### Configuración mínima (CPU)

```bash
./llama-server \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 4096 \
  --threads 8
```

### Con GPU NVIDIA (offload de capas)

```bash
./llama-server \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 8192 \
  --n-gpu-layers 35   # número de capas a offloadear a GPU; -1 = todas
  --threads 4
```

> **Regla práctica**: empieza con `--n-gpu-layers 999` y observa el log. Si la VRAM se agota, reduce el número hasta que cargue sin errores.

### Parámetros importantes

| Parámetro | Descripción |
|---|---|
| `--model` | Ruta al archivo .gguf |
| `--host` | IP de escucha (`0.0.0.0` = todas las interfaces) |
| `--port` | Puerto HTTP (por defecto 8080) |
| `--ctx-size` | Tamaño de ventana de contexto en tokens |
| `--threads` | Hilos de CPU para inferencia |
| `--n-gpu-layers` | Capas a procesar en GPU |
| `--parallel` | Peticiones simultáneas (slots) |
| `--api-key` | Clave API requerida en cabecera `Authorization` |

---

## Verificar que funciona

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [{"role": "user", "content": "Hola, ¿funcionas?"}],
    "max_tokens": 100
  }'
```

Respuesta esperada: objeto JSON con `choices[0].message.content`.

---

## Ejecutar como servicio systemd

```ini
# /etc/systemd/system/llama-server.service
[Unit]
Description=llama.cpp inference server
After=network.target

[Service]
Type=simple
User=llama
WorkingDirectory=/opt/llama-cpp
ExecStart=/opt/llama-cpp/llama-server \
    --model /opt/models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
    --host 127.0.0.1 \
    --port 8080 \
    --ctx-size 4096 \
    --threads 8 \
    --parallel 4
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now llama-server
sudo systemctl status llama-server
```

> **Nota de seguridad**: en producción, liga el servidor a `127.0.0.1` y expónlo solo a través del proxy inverso (ver [despliegue organizacional](05-organizacion.md)).

---

Siguiente: [vLLM — servidor de producción](04-vllm.md)
