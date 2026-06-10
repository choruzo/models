# Despliegue organizacional — Exponer el servidor a la red interna

Una vez que el motor de inferencia está funcionando en `localhost`, el siguiente paso es exponerlo de forma controlada a los usuarios y aplicaciones de la organización. Esta sección cubre la configuración del proxy inverso, autenticación, TLS interno y consideraciones específicas para entornos VMware.

## Arquitectura objetivo

```
Red interna de la organización
         │
         ▼  https://llm.empresa.local (443)
    Nginx (proxy inverso)
    ├── TLS con certificado interno
    ├── Autenticación por API key (cabecera Authorization)
    └── Rate limiting por IP
         │
         ▼  http://127.0.0.1:{8080|8000|11434}
    Motor de inferencia
    ├── llama-server  → :8080
    ├── vLLM          → :8000
    └── Ollama        → :11434
```

El motor **nunca** debe estar expuesto directamente en red. Solo escucha en `127.0.0.1` y nginx actúa como punto de entrada único.

---

## Nginx — Proxy inverso

### Instalación

```bash
sudo apt install nginx -y
```

### Configuración base (llama-server en :8080)

```nginx
# /etc/nginx/sites-available/llm
upstream llm_backend {
    server 127.0.0.1:8080;
    keepalive 16;
}

server {
    listen 443 ssl;
    server_name llm.empresa.local;

    # Certificado TLS interno (autofirmado o CA corporativa)
    ssl_certificate     /etc/ssl/certs/llm.empresa.local.crt;
    ssl_certificate_key /etc/ssl/private/llm.empresa.local.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # Autenticación por API key
    # Valida que la cabecera Authorization sea una de las claves permitidas
    set $valid_key 0;
    if ($http_authorization = "Bearer equipo-ia-2024")   { set $valid_key 1; }
    if ($http_authorization = "Bearer devops-team-key")  { set $valid_key 1; }

    if ($valid_key = 0) {
        return 401 '{"error": "Unauthorized"}';
    }

    # Rate limiting
    limit_req zone=llm_limit burst=20 nodelay;

    location /v1/ {
        proxy_pass         http://llm_backend;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;

        # Necesario para streaming (SSE)
        proxy_buffering    off;
        proxy_cache        off;
    }
}

# Redirigir HTTP → HTTPS
server {
    listen 80;
    server_name llm.empresa.local;
    return 301 https://$host$request_uri;
}
```

```nginx
# /etc/nginx/nginx.conf — añadir en el bloque http:
limit_req_zone $binary_remote_addr zone=llm_limit:10m rate=10r/s;
```

```bash
sudo ln -s /etc/nginx/sites-available/llm /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Ajuste según el motor

Cambia únicamente la línea `upstream` según el motor en uso:

```nginx
# vLLM
upstream llm_backend { server 127.0.0.1:8000; keepalive 16; }

# Ollama
upstream llm_backend { server 127.0.0.1:11434; keepalive 16; }
```

---

## Certificado TLS interno

### Opción A — Autofirmado (laboratorio / demo)

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout /etc/ssl/private/llm.empresa.local.key \
  -out /etc/ssl/certs/llm.empresa.local.crt \
  -subj "/CN=llm.empresa.local/O=Empresa/C=ES" \
  -addext "subjectAltName=DNS:llm.empresa.local"
```

Los clientes deberán aceptar el certificado o importar la CA.

### Opción B — CA corporativa (producción)

Si la organización tiene una CA interna (Microsoft ADCS, HashiCorp Vault PKI, etc.), genera una CSR y firma el certificado con ella. Todos los equipos del dominio ya confiarán en él.

```bash
# Generar clave y CSR
openssl req -new -newkey rsa:4096 -nodes \
  -keyout /etc/ssl/private/llm.empresa.local.key \
  -out /tmp/llm.empresa.local.csr \
  -subj "/CN=llm.empresa.local/O=Empresa/C=ES"
# Enviar el .csr a la CA corporativa para su firma
```

---

## DNS interno

Para que `llm.empresa.local` resuelva al servidor:

### Con servidor DNS interno (BIND, Windows DNS, pfSense)

Añade un registro A:
```
llm.empresa.local.  IN  A  192.168.1.50
```

### Sin DNS centralizado (solución rápida)

Añade la entrada en `/etc/hosts` de cada máquina cliente:

```
192.168.1.50  llm.empresa.local
```

En Windows: `C:\Windows\System32\drivers\etc\hosts`

---

## Gestión de API keys

Para un despliegue sencillo, las claves se gestionan en la configuración de nginx. Para algo más robusto, usa variables de entorno o un archivo externo:

```nginx
# Autenticación delegada a un archivo map
map $http_authorization $valid_api_key {
    "Bearer equipo-ia-2024"   1;
    "Bearer devops-team-key"  1;
    "Bearer readonly-user"    1;
    default                   0;
}

server {
    ...
    if ($valid_api_key = 0) {
        return 401 '{"error": {"message": "Invalid API key", "type": "invalid_request_error"}}';
    }
}
```

Rotar una clave es tan sencillo como eliminarla del mapa y recargar nginx (`nginx -s reload`) sin reiniciar el motor de inferencia.

---

## Consideraciones para entornos VMware

### Topología recomendada

```
┌─────────────────────────────────────┐
│  Host ESXi                          │
│  ┌──────────────────────────────┐   │
│  │  VM: llm-server              │   │
│  │  Ubuntu 22.04                │   │
│  │  ├── llama-server / vLLM     │   │
│  │  └── nginx                   │   │
│  │  vNIC → portgroup LLM-Infra  │   │
│  └──────────────────────────────┘   │
│                                     │
│  vSwitch / Distributed vSwitch      │
│  ├── portgroup: LLM-Infra (VLAN 50) │
│  └── portgroup: Gestión (VLAN 1)    │
└─────────────────────────────────────┘
         │ uplink
    Red corporativa (VLAN 50)
         │
    Clientes internos
```

### Puntos clave en VMware

- **VLAN dedicada**: segmenta el tráfico del servidor LLM del resto de la red con un portgroup y VLAN específicos.
- **vCPU para llama.cpp**: asigna al menos 8 vCPU si usas CPU-only; el rendimiento es proporcional a los hilos disponibles.
- **GPU Passthrough**: si el host tiene GPU NVIDIA, configura passthrough (VMDirectPath I/O) para vLLM. Una GPU pasada a una VM no puede compartirse con otras VMs simultáneamente.
- **VMXNET3**: usa el adaptador de red VMXNET3, no E1000, para reducir latencia en respuestas largas con streaming.
- **Balloon/Swap**: desactiva el balón de memoria (`sched.mem.maxmemctl = 0`) en la VM del servidor LLM. La paginación mata el rendimiento de inferencia.
- **Snapshots**: no tomes snapshots con el motor arriba y la GPU en passthrough activo; puede corromper el estado del driver.

### Hardware sizing orientativo

| Escenario | vCPU | RAM | Almacenamiento |
|---|---|---|---|
| llama.cpp CPU-only (7B Q4) | 8–16 | 16 GB | 20 GB |
| Ollama con GPU entry-level | 4–8 | 16 GB | 40 GB |
| vLLM producción (7B FP16) | 8–16 | 32 GB + GPU 16 GB VRAM | 60 GB |
| vLLM producción (70B FP16) | 16–32 | 64 GB + GPU 4×A100 | 200 GB |

---

## Verificación end-to-end

Desde un cliente en la red interna:

```bash
curl https://llm.empresa.local/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer equipo-ia-2024" \
  -d '{
    "model": "mistral-7b",
    "messages": [{"role": "user", "content": "¿El servidor funciona correctamente?"}],
    "max_tokens": 50
  }'
```

```python
# Test con OpenAI SDK
from openai import OpenAI

client = OpenAI(
    base_url="https://llm.empresa.local/v1",
    api_key="equipo-ia-2024",
)

response = client.chat.completions.create(
    model="mistral-7b",
    messages=[{"role": "user", "content": "Hola desde la red interna"}],
)
print(response.choices[0].message.content)
```

---

## Monitorización básica

```bash
# Estado del motor
sudo systemctl status llama-server   # o vllm / ollama

# Logs en tiempo real
sudo journalctl -fu llama-server

# Uso de GPU (si aplica)
watch -n 2 nvidia-smi

# Peticiones procesadas por nginx
sudo tail -f /var/log/nginx/access.log
```

---

Volver al [README](../README.md)
