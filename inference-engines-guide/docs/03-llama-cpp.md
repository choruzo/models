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

huggingface-cli download \
  bartowski/Mistral-7B-Instruct-v0.3-GGUF \
  Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --local-dir ./models
```

---

## Arrancar llama-server

### CPU-only

```bash
./llama-server \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 4096 \
  --threads 8
```

### Con GPU NVIDIA

```bash
./llama-server \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 8192 \
  --n-gpu-layers 35 \
  --threads 4
```

> Empieza con `--n-gpu-layers 999` y observa el log. Si la VRAM se agota, reduce hasta que cargue sin errores.

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
```

> En producción, liga el servidor a `127.0.0.1` y expónlo a través del proxy inverso (ver [despliegue organizacional](05-organizacion.md)).

---

## Referencia de flags

### Modelo y carga

| Flag | Valores | Descripción |
|---|---|---|
| `--model` | ruta | Archivo GGUF a cargar |
| `--model-alias` | string | Nombre que se devuelve en `/v1/models` |
| `--n-gpu-layers` / `-ngl` | entero / `-1` | Capas a offloadear a GPU; `-1` = todas |
| `--split-mode` | `none` / `layer` / `row` | Cómo distribuir capas en multi-GPU |
| `--tensor-split` | `3,1` | Proporción de VRAM por GPU (ej. 75%/25%) |
| `--main-gpu` | índice | GPU principal para operaciones no repartidas |
| `--no-mmap` | flag | Desactiva memory-map; carga el modelo completo en RAM |
| `--mlock` | flag | Fija el modelo en RAM, impide que el SO lo pagine |
| `--numa` | `distribute` / `isolate` / `numactl` | Estrategia de afinidad NUMA (servidores multi-socket) |

### Contexto y memoria KV

| Flag | Valores | Descripción |
|---|---|---|
| `--ctx-size` / `-c` | tokens (pot. de 2) | Tamaño de la ventana de contexto |
| `--batch-size` / `-b` | tokens | Tokens procesados en paralelo en prompt processing |
| `--ubatch-size` / `-ub` | tokens | Micro-batch; ajusta uso de VRAM durante PP |
| `--cache-type-k` | `f16` / `q8_0` / `q4_0` | Precision del KV cache (keys) |
| `--cache-type-v` | `f16` / `q8_0` / `q4_0` | Precision del KV cache (values) |
| `--flash-attn` / `-fa` | flag | Flash Attention; reduce VRAM del KV cache ~50% |
| `--rope-scaling` | `none` / `linear` / `yarn` | Metodo de extension de contexto |
| `--rope-scale` | float | Factor de escalado RoPE |
| `--yarn-ext-factor` | float | Factor de extrapolacion YaRN |

### Rendimiento CPU

| Flag | Valores | Descripción |
|---|---|---|
| `--threads` / `-t` | entero | Hilos para token generation |
| `--threads-batch` / `-tb` | entero | Hilos para prompt processing (suele ser mayor que `-t`) |
| `--cpu-mask` | hex mask | Afinidad de CPU (ej. `0xFF` = primeros 8 núcleos) |
| `--poll` | 0-100 | % de busy-wait; reduce latencia a costa de CPU |

### Servidor y concurrencia

| Flag | Valores | Descripción |
|---|---|---|
| `--host` | IP | Interfaz de escucha |
| `--port` | entero | Puerto HTTP |
| `--parallel` / `-np` | entero | Slots de inferencia simultaneos |
| `--cont-batching` | flag | Varios usuarios comparten un batch |
| `--api-key` | string | Clave requerida en `Authorization: Bearer` |
| `--timeout` | segundos | Tiempo maximo de respuesta |
| `--log-disable` | flag | Silencia el log de peticiones |

### Sampling (defaults del servidor)

| Flag | Valores | Descripción |
|---|---|---|
| `--temp` | 0.0-2.0 | Temperatura; 0 = determinista |
| `--top-k` | entero | Limita a los K tokens mas probables |
| `--top-p` | 0.0-1.0 | Nucleus sampling |
| `--min-p` | 0.0-1.0 | Descarta tokens con prob < P × max |
| `--repeat-penalty` | float | Penaliza repeticion de tokens recientes |
| `--repeat-last-n` | entero | Ventana de tokens para repeat-penalty |

---

## Optimizaciones

### CPU-only: máximo rendimiento

El cuello de botella en CPU es el ancho de banda de memoria, no la potencia de computo. El modelo pasa completo por RAM en cada token generado.

```bash
./llama-server \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --ctx-size 4096 \
  --threads 6 \
  --threads-batch 12 \
  --batch-size 512 \
  --mlock \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --cont-batching
```

**`--threads` < nucleos totales**: reservar 1-2 nucleos para el SO evita que el planificador interrumpa la inferencia. En un servidor de 8 nucleos fisicos, empieza con `-t 6`.

**`--threads-batch` > `--threads`**: el prompt processing es altamente paralelizable, la generacion token a token no. Usa todos los hilos disponibles para PP y menos para TG.

**KV cache cuantizado** (`q8_0`): reduce la RAM del contexto ~50% con perdida de calidad negligible en la gran mayoria de modelos.

### CPU multi-socket (NUMA)

En servidores con 2+ sockets fisicos, el acceso a RAM del socket remoto es 2-3x mas lento:

```bash
# Opcion A: flag integrado
./llama-server --numa distribute ...

# Opcion B: fijar al socket 0 con numactl
numactl --cpunodebind=0 --membind=0 ./llama-server ...
```

Verificar la topologia NUMA del sistema:

```bash
numactl --hardware
lscpu | grep NUMA
```

### GPU: maximizar uso de VRAM

Cuantas mas capas en GPU, menos viajes a RAM. El objetivo es poner el maximo posible:

```bash
./llama-server \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --n-gpu-layers 999 \
  --flash-attn \
  --cache-type-k q8_0 \
  --ctx-size 8192 \
  --threads 4 \
  --cont-batching
```

**Flash Attention** es especialmente valiosa con contextos largos: el KV cache crece linealmente con el contexto y Flash Attention evita materializarlo completo en VRAM.

### Multi-GPU

```bash
# 2 GPUs: 70% de capas en GPU 0, 30% en GPU 1
./llama-server \
  --model ./models/llama-3-70b-Q4_K_M.gguf \
  --n-gpu-layers 999 \
  --split-mode layer \
  --tensor-split 7,3 \
  --main-gpu 0
```

`--split-mode row` distribuye por filas de matrices en vez de por capas; puede ser mas eficiente en modelos con capas muy grandes (MoE, 70B+).

### Cuantizacion segun hardware

| Escenario | Cuantizacion recomendada | Motivo |
|---|---|---|
| CPU, RAM ajustada | Q4_K_M | Mejor relacion calidad/tamaño |
| CPU, RAM holgada | Q6_K | Calidad muy cercana a F16 |
| GPU con VRAM justa | Q4_K_M o Q5_K_M | Mas capas en GPU |
| GPU con VRAM amplia | Q8_0 | Calidad casi identica a F16 |
| Embeddings / RAG | F16 | Maxima precision para vectores |

---

## Benchmark con llama-bench

`llama-bench` mide dos metricas clave:

- **PP (prompt processing)**: tokens/s al procesar el prompt de entrada
- **TG (token generation)**: tokens/s al generar la respuesta

```bash
./llama-bench \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --n-gpu-layers 35 \
  --threads 8

# Salida tipica:
# model           | size     | params | backend | ngl | test  |     t/s
# Mistral 7B Q4KM | 4.07 GiB | 7.24 B | CUDA    |  35 | pp512 | 1842.45
# Mistral 7B Q4KM | 4.07 GiB | 7.24 B | CUDA    |  35 | tg128 |   52.31
```

### Barrer configuraciones

```bash
# Encontrar el numero optimo de capas en GPU
./llama-bench \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --n-gpu-layers 0,10,20,33,35 \
  --threads 8 \
  --output-format csv > bench-capas.csv
```

```bash
# Comparar cuantizaciones
./llama-bench \
  --model ./models/Mistral-7B-Q4_K_M.gguf \
  --model ./models/Mistral-7B-Q8_0.gguf \
  --n-gpu-layers 35
```

```bash
# Barrer batch-size para prompt processing
./llama-bench \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --batch-size 128,256,512,1024 \
  --n-prompt 512 \
  --n-gen 0
```

```bash
# Barrer numero de hilos CPU
./llama-bench \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --threads 2,4,6,8,12,16 \
  --n-gen 128 \
  --n-prompt 0
```

### Parametros de llama-bench

| Parametro | Descripcion |
|---|---|
| `--n-prompt` | Tokens de prompt a procesar (default 512) |
| `--n-gen` | Tokens a generar (default 128) |
| `--n-gpu-layers` | Acepta lista por comas para barrer |
| `--batch-size` | Acepta lista por comas |
| `--threads` | Acepta lista por comas |
| `--repetitions` | Repeticiones para promediar (default 5) |
| `--output-format` | `md` (tabla) o `csv` |
| `--verbose` | Muestra configuracion completa y uso de memoria |

### Interpretar resultados

| TG (tokens/s) | Valoracion |
|---|---|
| > 50 | Excelente; respuesta casi instantanea |
| 20-50 | Bueno; fluido para chat interactivo |
| 10-20 | Aceptable; perceptible pero usable |
| < 10 | Solo viable para tareas batch o no interactivas |

Si **PP es alto pero TG es bajo**: el cuello de botella es la generacion token a token (limitada por ancho de banda de RAM en CPU, o por tamaño del modelo en GPU). Si **ambos son bajos**: el modelo no cabe bien en los recursos asignados.

---

## Encontrar el contexto adecuado

### Coste en memoria del KV cache

El KV cache crece linealmente con el contexto. Formula aproximada para un modelo en FP16:

```
KV cache (GB) ≈ (2 × num_layers × num_heads × head_dim × ctx_size × 2) / 1024^3
```

Para Mistral 7B (32 capas) con KV en F16:

| ctx-size | KV cache F16 | KV cache Q8 |
|---|---|---|
| 2 048 | ~256 MB | ~128 MB |
| 4 096 | ~512 MB | ~256 MB |
| 8 192 | ~1.0 GB | ~512 MB |
| 16 384 | ~2.0 GB | ~1.0 GB |
| 32 768 | ~4.0 GB | ~2.0 GB |

### Impacto en velocidad (CPU)

En CPU, mas contexto = mas datos que recorrer en cada token generado:

```bash
./llama-bench \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --ctx-size 2048,4096,8192,16384 \
  --n-prompt 0 \
  --n-gen 128 \
  --threads 8
```

En GPU el impacto es menor gracias a Flash Attention.

### Contexto segun caso de uso

| Caso de uso | ctx-size recomendado |
|---|---|
| Chat conversacional | 4 096 - 8 192 |
| Resumir documentos | 16 384 - 32 768 |
| RAG (solo el chunk) | 2 048 - 4 096 |
| Analisis de codigo | 8 192 - 32 768 |
| Agentes con tool calls | 8 192 - 16 384 |

### Extender el contexto con RoPE scaling

Para ir mas alla del contexto nativo del modelo sin reentrenar:

```bash
# YaRN: el metodo mas estable para extension de contexto
./llama-server \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --ctx-size 65536 \
  --rope-scaling yarn \
  --yarn-ext-factor 1.0 \
  --rope-scale 2.0
```

`--rope-scale` = ctx_objetivo / ctx_nativo del modelo. Extender mas de 4x el contexto nativo degrada visiblemente la calidad; el modelo pierde coherencia en los extremos.

### Medir tokens reales de un texto

Un token equivale aproximadamente a 0.75 palabras en español, pero la cifra exacta depende del tokenizador. Para medir con precision:

```bash
echo "Tu texto aqui" | ./llama-tokenize \
  --model ./models/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf \
  --stdin
```

O directamente via API del servidor en marcha:

```bash
curl http://localhost:8080/tokenize \
  -H "Content-Type: application/json" \
  -d '{"content": "Tu texto aqui"}'
```

**Proceso recomendado para elegir ctx-size**:

1. Identifica el caso de uso mas largo (prompt del sistema + historial + documento + respuesta maxima).
2. Mide los tokens reales con `llama-tokenize` sobre ejemplos representativos.
3. Añade un 20% de margen y redondea a la potencia de 2 mas cercana.
4. Mide el impacto en TG con `llama-bench` a ese ctx-size antes de fijarlo en produccion.

---

Siguiente: [vLLM — servidor de produccion](04-vllm.md)
