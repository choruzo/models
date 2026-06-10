# Conceptos: Motores de Inferencia LLM

## ¿Qué es un motor de inferencia?

Un motor de inferencia es el proceso que carga un modelo de lenguaje en memoria (RAM o VRAM) y atiende peticiones de generación de texto. Expone una API HTTP, generalmente compatible con la API de OpenAI, para que cualquier aplicación pueda consumirlo sin depender de servicios en la nube.

```
Aplicación / usuario
       │  POST /v1/chat/completions
       ▼
Motor de inferencia (llama.cpp | vLLM | Ollama)
       │  carga pesos del modelo
       ▼
CPU / GPU / memoria
```

La API compatible con OpenAI es el estándar de facto. Cualquier cliente que funcione contra `api.openai.com` funciona contra un motor local cambiando únicamente la `base_url` y la `api_key`.

---

## Comparativa de los tres motores

### llama.cpp / llama-server

- **Origen**: proyecto C++ de Georgi Gerganov, comunidad open source
- **Formato de modelo**: GGUF (cuantizado, pesos comprimidos a 2–8 bits)
- **Aceleración**: CPU (AVX2/AVX512), GPU NVIDIA (CUDA), AMD (ROCm), Apple (Metal)
- **API**: HTTP compatible con OpenAI, WebSocket para streaming
- **Footprint**: binario único ~10 MB, sin dependencias Python
- **Ideal para**: hardware modesto, servidores sin GPU, edge, laboratorios

### vLLM

- **Origen**: UC Berkeley, ampliamente adoptado en producción enterprise
- **Formato de modelo**: modelos HuggingFace en precisión nativa (FP16/BF16) o cuantizados (GPTQ, AWQ)
- **Aceleración**: NVIDIA exclusivamente (CUDA), soporte AMD experimental
- **API**: servidor OpenAI-compatible con soporte de batching continuo (*continuous batching*)
- **Rendimiento**: el más alto de los tres en throughput cuando hay múltiples usuarios concurrentes
- **Ideal para**: producción, múltiples usuarios simultáneos, GPUs de datacenter

### Ollama

- **Origen**: proyecto Go orientado a simplicidad, similar a "Docker para modelos"
- **Formato de modelo**: GGUF bajo el capó + registro propio (`ollama.com/library`)
- **Aceleración**: CPU, NVIDIA, AMD, Apple Silicon
- **API**: REST propia (`/api/generate`, `/api/chat`) + capa compatible con OpenAI (`/v1/`)
- **Footprint**: instalador único, daemon systemd incluido, sin configuración
- **Ideal para**: despliegues rápidos, equipos de desarrollo, demos internas

---

## Cuándo usar cada uno

| Escenario | Recomendación |
|---|---|
| Sin GPU, servidor físico o VM | llama.cpp |
| GPU NVIDIA en producción con varios usuarios | vLLM |
| Despliegue rápido sin configuración | Ollama |
| Control fino de parámetros por petición | llama.cpp o vLLM |
| Integración con LangChain / LlamaIndex | Los tres (API OpenAI-compatible) |
| Equipos VMware con VMs sin GPU passthrough | llama.cpp o Ollama (CPU) |
| Host ESXi con GPU passthrough a una VM | vLLM o llama.cpp con CUDA |

---

## El formato GGUF

GGUF es el formato de serialización de llama.cpp (y Ollama). Un mismo modelo puede existir en distintas cuantizaciones:

| Cuantización | Calidad | RAM aprox. (7B) |
|---|---|---|
| Q2_K | Baja | ~3 GB |
| Q4_K_M | Buena relación calidad/tamaño | ~5 GB |
| Q5_K_M | Alta | ~6 GB |
| Q8_0 | Casi full precision | ~8 GB |
| F16 | Full precision | ~14 GB |

La variante `Q4_K_M` es el punto de partida recomendado: buena calidad con RAM razonable.

Los modelos GGUF se descargan desde [Hugging Face](https://huggingface.co/) (buscar `gguf` en el filtro de formato) o directamente con `huggingface-cli`.

---

Siguiente: [Ollama — servidor simplificado](02-ollama.md)
