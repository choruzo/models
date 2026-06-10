# Motores de Inferencia LLM — Guía de Despliegue Organizacional

Guía práctica para levantar servidores de inferencia con modelos de lenguaje (LLM) y exponerlos de forma controlada a una organización. Cubre tres motores principales ordenados de menor a mayor requisito de hardware.

## Motores documentados

| Motor | Ideal para | Hardware mínimo |
|---|---|---|
| [Ollama](docs/02-ollama.md) | Despliegue rápido, dev interno | CPU o GPU entry-level |
| [llama.cpp / llama-server](docs/03-llama-cpp.md) | Edge, hardware modesto, control fino | CPU moderna (GGUF cuantizado) |
| [vLLM](docs/04-vllm.md) | Producción, alto throughput | NVIDIA GPU 16 GB+ VRAM |

## Estructura

```
inference-engines-guide/
├── README.md                   ← Este archivo
└── docs/
    ├── 01-conceptos.md         ← Qué es un motor de inferencia, comparativa
    ├── 02-ollama.md            ← Instalación y servidor Ollama
    ├── 03-llama-cpp.md         ← Instalación y servidor llama.cpp
    ├── 04-vllm.md              ← Instalación y servidor vLLM
    └── 05-organizacion.md      ← Exponerlos a una organización (nginx, auth, red)
```

## Flujo general

```
Modelo (GGUF / HuggingFace / Ollama registry)
        │
        ▼
Motor de inferencia  ←── llama-server | vLLM | Ollama
        │
        ▼  :8080 / :8000 / :11434
Nginx reverse proxy  ←── TLS + autenticación API key
        │
        ▼  https://llm.empresa.local
Usuarios / aplicaciones internas
```

## Secciones

1. [Conceptos y comparativa](docs/01-conceptos.md)
2. [Ollama — servidor simplificado](docs/02-ollama.md)
3. [llama.cpp — servidor optimizable](docs/03-llama-cpp.md)
4. [vLLM — servidor de producción](docs/04-vllm.md)
5. [Despliegue organizacional](docs/05-organizacion.md)

---

> Mantenido por [Javi](https://github.com/tu-usuario) · Infraestructura VMware & AI
