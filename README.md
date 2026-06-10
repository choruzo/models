# Repositorio de Modelos Locales

Este proyecto es mi espacio documental para aprender, probar y comparar inferencia local de LLMs.

El objetivo es centralizar en un solo lugar:

- Apuntes técnicos sobre motores de inferencia.
- Experimentos reales con modelos GGUF.
- Scripts para lanzar modelos y medir rendimiento.
- Resultados y conclusiones en formato reproducible.

## Enfoque del repo

Este no es un producto ni una libreria publica. Es un laboratorio personal de investigacion aplicada, orientado a:

- Entender trade-offs de calidad, latencia y consumo de memoria.
- Comparar modelos cuantizados en hardware local.
- Definir una base practica para despliegues internos.

## Estructura principal

```text
.
├── inference-engines-guide/      # Guia documental de motores de inferencia
│   ├── README.md
│   └── docs/
│       ├── 01-conceptos.md
│       ├── 02-ollama.md
│       ├── 03-llama-cpp.md
│       ├── 04-vllm.md
│       └── 05-organizacion.md
├── litellm/                      # Entorno y pruebas alrededor de LiteLLM
├── launch-*.ps1                  # Scripts de lanzamiento de modelos
├── bench-*.ps1                   # Scripts de benchmark
├── bench-results-*.csv           # Resultados de mediciones
└── *.gguf                        # Modelos locales cuantizados
```

## Documentacion

La base teorica y operativa esta en:

- `inference-engines-guide/README.md`
- `inference-engines-guide/docs/01-conceptos.md`
- `inference-engines-guide/docs/02-ollama.md`
- `inference-engines-guide/docs/03-llama-cpp.md`
- `inference-engines-guide/docs/04-vllm.md`
- `inference-engines-guide/docs/05-organizacion.md`

## Flujo de trabajo habitual

1. Seleccionar un modelo GGUF para la prueba.
2. Lanzar inferencia con un script `launch-*.ps1`.
3. Ejecutar benchmark con un script `bench-*.ps1`.
4. Guardar resultados en CSV.
5. Documentar observaciones y decisiones.

## Scripts disponibles (resumen)

- `launch-gemma4-12b.ps1`
- `launch-gpt-oss-20b.ps1`
- `launch-qwen.ps1`
- `launch-qwen3-9b.ps1`
- `bench-perplexity.ps1`
- `bench-qwen.ps1`

Nota: los scripts pueden requerir rutas locales o parametros concretos segun la maquina.

## Convenciones recomendadas para nuevos experimentos

- Mantener nombres de archivo con fecha u objetivo (`bench-results-YYYYMMDD-HHMM.csv`).
- Registrar siempre modelo, cuantizacion y contexto de hardware.
- Guardar un breve resumen de hallazgos junto a cada bloque de resultados.

## Estado

Repositorio en evolucion continua. El contenido se ira refinando conforme se consoliden pruebas y comparativas.
