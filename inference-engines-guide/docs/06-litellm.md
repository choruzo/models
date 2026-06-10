# LiteLLM Proxy — Un endpoint, múltiples modelos

LiteLLM Proxy expone una única API OpenAI-compatible que enruta las peticiones hacia cualquier backend: llama.cpp, vLLM, Ollama, OpenAI, Anthropic, etc. Para los clientes y aplicaciones, solo existe un endpoint; LiteLLM decide a qué modelo real dirigir cada petición.

```
Clientes / aplicaciones
        │  POST /v1/chat/completions  {"model": "mistral-local"}
        ▼
  LiteLLM Proxy  :4000
  ├── model: mistral-local   → llama-server  :8080
  ├── model: llama3-gpu      → vLLM          :8000
  ├── model: qwen-ollama     → Ollama        :11434
  └── model: gpt-4o          → OpenAI API
```

---

## Instalación

```bash
pip install litellm[proxy] --break-system-packages

# Verificar
litellm --version
```

---

## Configuración: config.yaml

Toda la configuración del proxy vive en un archivo YAML. Este es el punto central de control.

### Estructura básica

```yaml
# config.yaml
model_list:
  - model_name: mistral-local
    litellm_params:
      model: openai/mistral
      api_base: http://127.0.0.1:8080/v1
      api_key: "no-key"

  - model_name: llama3-gpu
    litellm_params:
      model: openai/llama3
      api_base: http://127.0.0.1:8000/v1
      api_key: "tu-api-key-vllm"

  - model_name: qwen-ollama
    litellm_params:
      model: ollama/qwen2.5:7b
      api_base: http://127.0.0.1:11434

litellm_settings:
  drop_params: true        # ignora parametros no soportados por cada backend
  request_timeout: 300

general_settings:
  master_key: "sk-org-master-key-2024"   # clave admin del proxy
```

El prefijo `openai/` indica a LiteLLM que el backend usa la API OpenAI-compatible. El nombre real del modelo (lo que ve el backend) va en `model:`; el alias que usan los clientes va en `model_name:`.

### Arrancar el proxy

```bash
litellm --config config.yaml --port 4000

# Con logs reducidos para produccion
litellm --config config.yaml --port 4000 --detailed_debug false
```

---

## Load balancing — múltiples instancias del mismo modelo

Si tienes varias instancias del mismo motor (ej. dos servidores llama.cpp), LiteLLM reparte la carga automáticamente:

```yaml
model_list:
  - model_name: mistral          # nombre publico unico
    litellm_params:
      model: openai/mistral
      api_base: http://192.168.1.10:8080/v1
      api_key: "no-key"
      weight: 2                  # recibe el doble de peticiones

  - model_name: mistral          # mismo model_name = mismo pool
    litellm_params:
      model: openai/mistral
      api_base: http://192.168.1.11:8080/v1
      api_key: "no-key"
      weight: 1

router_settings:
  routing_strategy: least-busy   # opciones: simple-shuffle, least-busy, latency-based-routing
  num_retries: 2
  timeout: 120
```

Las estrategias de routing disponibles son `simple-shuffle` (round-robin aleatorio), `least-busy` (menor cola) y `latency-based-routing` (el que responde más rápido históricamente).

---

## Fallbacks — degradación controlada

Si el modelo preferido falla o está saturado, LiteLLM redirige a una alternativa:

```yaml
model_list:
  - model_name: llama3-gpu
    litellm_params:
      model: openai/llama3
      api_base: http://127.0.0.1:8000/v1
      api_key: "clave-vllm"

  - model_name: llama3-cpu
    litellm_params:
      model: openai/llama3
      api_base: http://127.0.0.1:8080/v1
      api_key: "no-key"

litellm_settings:
  fallbacks:
    - {"llama3-gpu": ["llama3-cpu"]}   # si falla GPU, usa CPU
  context_window_fallbacks:
    - {"llama3-gpu": ["llama3-cpu"]}   # si el contexto excede el limite, usa alternativa
  num_retries: 3
  retry_after: 5
```

---

## Gestión de claves de API por equipo

LiteLLM permite emitir claves individuales con límites propios, sin exponer la master key:

```bash
# Crear una clave para el equipo de IA con rate limit
curl http://localhost:4000/key/generate \
  -H "Authorization: Bearer sk-org-master-key-2024" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "equipo-ia",
    "models": ["mistral-local", "llama3-gpu"],
    "max_budget": 10.0,
    "rpm_limit": 60,
    "tpm_limit": 100000
  }'

# Crear una clave de solo lectura para devops
curl http://localhost:4000/key/generate \
  -H "Authorization: Bearer sk-org-master-key-2024" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "devops-readonly",
    "models": ["mistral-local"],
    "rpm_limit": 10
  }'
```

Las claves generadas tienen el formato `sk-...` y se usan exactamente igual que una API key de OpenAI:

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-xxxxxxxxxxxx" \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-local", "messages": [{"role": "user", "content": "Hola"}]}'
```

---

## Configuración completa de producción

```yaml
# config.yaml — produccion
model_list:
  # llama.cpp CPU (disponibilidad maxima)
  - model_name: mistral-fast
    litellm_params:
      model: openai/mistral
      api_base: http://127.0.0.1:8080/v1
      api_key: "clave-llama"
      timeout: 120

  # vLLM GPU (alto rendimiento)
  - model_name: mistral-fast
    litellm_params:
      model: openai/mistral-7b
      api_base: http://127.0.0.1:8000/v1
      api_key: "clave-vllm"
      timeout: 60
      weight: 3

  # Ollama (modelos especializados)
  - model_name: code-assistant
    litellm_params:
      model: ollama/qwen2.5-coder:7b
      api_base: http://127.0.0.1:11434
      timeout: 180

  # OpenAI como fallback externo (solo si falla todo lo local)
  - model_name: fallback-cloud
    litellm_params:
      model: gpt-4o-mini
      api_key: "sk-openai-..."

router_settings:
  routing_strategy: least-busy
  num_retries: 2
  retry_after: 3
  allowed_fails: 3              # instancias con 3 fallos se marcan como degradadas
  cooldown_time: 60             # segundos antes de reintentar una instancia degradada

litellm_settings:
  drop_params: true
  request_timeout: 300
  fallbacks:
    - {"mistral-fast": ["fallback-cloud"]}
  success_callback: ["langfuse"]   # trazabilidad opcional
  failure_callback: ["langfuse"]

general_settings:
  master_key: "sk-org-master-key-2024"
  database_url: "postgresql://litellm:password@localhost:5432/litellm"  # persistencia de claves
  store_model_in_db: true
```

---

## Ejecutar como servicio systemd

```ini
# /etc/systemd/system/litellm.service
[Unit]
Description=LiteLLM Proxy
After=network.target llama-server.service

[Service]
Type=simple
User=litellm
WorkingDirectory=/opt/litellm
ExecStart=/opt/litellm/venv/bin/litellm \
    --config /opt/litellm/config.yaml \
    --port 4000
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now litellm
```

---

## Integrar con nginx

LiteLLM reemplaza la necesidad de configurar nginx por motor individualmente. Con proxy se apunta nginx a un solo upstream:

```nginx
upstream litellm {
    server 127.0.0.1:4000;
}

server {
    listen 443 ssl;
    server_name llm.empresa.local;

    ssl_certificate     /etc/ssl/certs/llm.empresa.local.crt;
    ssl_certificate_key /etc/ssl/private/llm.empresa.local.key;

    location / {
        proxy_pass         http://litellm;
        proxy_read_timeout 300s;
        proxy_buffering    off;   # streaming SSE
    }
}
```

La autenticacion por clave la gestiona LiteLLM internamente; nginx solo hace TLS y puede eliminar la capa de validacion de `Authorization` que tenia antes.

---

## Panel de administración (UI)

LiteLLM incluye una UI web en `http://localhost:4000/ui`:

```bash
# Habilitar en config.yaml
general_settings:
  master_key: "sk-org-master-key-2024"
  ui_access_mode: "admin_only"   # opciones: public, admin_only
```

Desde la UI puedes ver peticiones en tiempo real, gestionar claves, consultar uso por equipo y configurar modelos sin reiniciar el proxy.

---

## Verificar el proxy

```bash
# Listar modelos disponibles
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer sk-org-master-key-2024"

# Test de chat
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-org-master-key-2024" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-fast",
    "messages": [{"role": "user", "content": "responde con una palabra: funciona?"}],
    "max_tokens": 10
  }'

# Health check
curl http://localhost:4000/health
```

---

## Arquitectura final con LiteLLM

```
Red interna de la organizacion
         |
         v  https://llm.empresa.local (443)
    Nginx  (TLS)
         |
         v  http://127.0.0.1:4000
    LiteLLM Proxy
    |- Autenticacion por API key por equipo
    |- Routing / load balancing / fallbacks
    |- Observabilidad (logs, metricas)
         |
    .----|----.-----------.
    |         |           |
    v         v           v
llama-server vLLM       Ollama
  :8080      :8000      :11434
