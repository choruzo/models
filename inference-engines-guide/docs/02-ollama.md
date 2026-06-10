# Ollama — Servidor simplificado

Ollama es la opción más rápida de desplegar. Funciona como un daemon del sistema con un registro de modelos propio y expone tanto su API nativa como una capa compatible con OpenAI.

## Requisitos

- Linux / macOS / Windows
- CPU moderna (sin GPU funciona correctamente para modelos pequeños)
- GPU NVIDIA (CUDA), AMD (ROCm) o Apple Silicon soportados automáticamente

---

## Instalación

### Linux (recomendado para servidores)

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

El instalador:
- Descarga el binario a `/usr/local/bin/ollama`
- Crea el usuario `ollama`
- Registra y arranca el servicio `ollama.service` en systemd

Verificar:

```bash
systemctl status ollama
ollama --version
```

### Sin script (instalación manual)

```bash
# Descargar binario directamente
curl -L https://ollama.com/download/ollama-linux-amd64.tgz | tar -xz -C /usr/local/bin

# Crear servicio manualmente
sudo useradd -r -s /bin/false -m -d /usr/share/ollama ollama
```

---

## Descargar y ejecutar un modelo

```bash
# Descarga el modelo y lanza una sesión de chat interactiva
ollama run llama3.2

# Solo descarga sin abrir chat
ollama pull llama3.2
ollama pull mistral
ollama pull qwen2.5:7b
```

Modelos disponibles en [ollama.com/library](https://ollama.com/library).

Listar modelos locales:

```bash
ollama list
```

---

## Configuración de red

Por defecto, Ollama escucha solo en `127.0.0.1:11434`. Para exponerlo en red:

```bash
# Editar el servicio systemd
sudo systemctl edit ollama
```

Añadir en el archivo que se abre:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

> En producción, deja `OLLAMA_HOST=127.0.0.1:11434` y expón el servicio a través de nginx (ver [despliegue organizacional](05-organizacion.md)).

---

## Modelfile — personalización de modelos

Un `Modelfile` permite derivar modelos con instrucciones del sistema, parámetros o adaptadores propios:

```dockerfile
# Modelfile
FROM mistral

SYSTEM """
Eres un asistente técnico especializado en infraestructura VMware.
Responde siempre en español y en formato conciso.
"""

PARAMETER temperature 0.3
PARAMETER num_ctx 8192
```

```bash
ollama create vmware-assistant -f Modelfile
ollama run vmware-assistant
```

---

## API REST nativa

```bash
# Chat con historial
curl http://localhost:11434/api/chat \
  -d '{
    "model": "mistral",
    "messages": [{"role": "user", "content": "Hola"}],
    "stream": false
  }'

# Generar texto (sin historial)
curl http://localhost:11434/api/generate \
  -d '{"model": "mistral", "prompt": "Hola", "stream": false}'
```

## API compatible con OpenAI

Ollama expone `/v1/` con compatibilidad OpenAI desde la versión 0.1.24:

```bash
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ollama" \   # cualquier string funciona
  -d '{
    "model": "mistral",
    "messages": [{"role": "user", "content": "Hola"}]
  }'
```

Esto permite usar Ollama con cualquier SDK o herramienta que acepte una `base_url` personalizada (LangChain, OpenAI Python SDK, etc.):

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama",
)

response = client.chat.completions.create(
    model="mistral",
    messages=[{"role": "user", "content": "Hola"}]
)
print(response.choices[0].message.content)
```

---

## Variables de entorno útiles

| Variable | Descripción | Ejemplo |
|---|---|---|
| `OLLAMA_HOST` | IP y puerto de escucha | `0.0.0.0:11434` |
| `OLLAMA_MODELS` | Directorio de modelos | `/data/ollama/models` |
| `OLLAMA_NUM_PARALLEL` | Peticiones simultáneas | `4` |
| `OLLAMA_MAX_LOADED_MODELS` | Modelos cargados en memoria a la vez | `2` |
| `OLLAMA_KEEP_ALIVE` | Tiempo que un modelo permanece en memoria | `5m` |

Configurar en el servicio:

```bash
sudo systemctl edit ollama
```

```ini
[Service]
Environment="OLLAMA_MODELS=/data/ollama/models"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_KEEP_ALIVE=10m"
```

---

## Gestión de modelos

```bash
ollama list                  # listar modelos locales
ollama show mistral          # detalles de un modelo
ollama rm mistral            # eliminar modelo
ollama cp mistral mi-modelo  # copiar (base para Modelfile)
```

---

Siguiente: [llama.cpp — servidor optimizable](03-llama-cpp.md)
