# Lab local — Windows + Ubuntu VM + Grafana/Prometheus

Setup completo del stack en tu equipo: llama.cpp sirviendo Qwen3.5-9B en Windows,
LiteLLM como proxy en una VM Ubuntu (NAT), nginx con TLS, y observabilidad con
Prometheus + Grafana.

```
Windows (host)                     VM Ubuntu (NAT)
─────────────────                  ─────────────────────────────────────
llama-server :8080  ──────────────► LiteLLM :4000
G:\models\Qwen3.5-9B-Q8_0.gguf    nginx :443  (TLS autofirmado)
                                   Prometheus :9090
                                   Grafana :3000
```

---

## Paso 0 — Encontrar la IP del host Windows desde la VM (NAT)

Con NAT, la VM accede al host a través del adaptador VMnet8.

En Windows (PowerShell):

```powershell
ipconfig | Select-String "VMnet8" -A 3
```

Busca la línea **Dirección IPv4** del adaptador "VMware Network Adapter VMnet8".
Suele ser `192.168.x.1`. Anota esa IP — la usarás en toda la configuración de la VM.

Para confirmar desde la VM Ubuntu:

```bash
ping 192.168.x.1   # sustituye por tu IP real
```

---

## Paso 1 — Windows: exponer llama-server en red

El script `launch-qwen3-9b.ps1` actual vincula el servidor a `127.0.0.1`, por lo
que la VM no puede alcanzarlo. Crea una variante para el lab:

```powershell
# G:\models\launch-qwen3-9b-lab.ps1
# Igual que launch-qwen3-9b.ps1 pero escucha en todas las interfaces

param(
    [ValidateSet("32k", "64k", "128k")]
    [string]$Context = "64k",
    [int]$Port    = 8080,
    [int]$Threads = 8
)

$LlamaBin  = "D:\Archivos\Javier\Scritp_python\Agente\llama_cpp_server\build\bin\Release\llama-server.exe"
$ModelPath = "G:\models\Qwen3.5-9B-Q8_0.gguf"

if (-not (Test-Path $LlamaBin))  { Write-Error "No se encuentra llama-server"; exit 1 }
if (-not (Test-Path $ModelPath)) { Write-Error "No se encuentra el modelo";    exit 1 }

switch ($Context) {
    "32k"  { $CtxSize = 32768;  $KvType = "q8_0" }
    "64k"  { $CtxSize = 65536;  $KvType = "q8_0" }
    "128k" { $CtxSize = 131072; $KvType = "q4_0" }
}

Write-Host "Iniciando en red — accesible desde VM en puerto $Port"

& $LlamaBin `
    --model         $ModelPath `
    --ctx-size      $CtxSize `
    --n-gpu-layers  99 `
    --cache-type-k  $KvType `
    --cache-type-v  $KvType `
    --flash-attn    on `
    --threads       $Threads `
    --batch-size    512 `
    --ubatch-size   512 `
    --host          "0.0.0.0" `   # <-- cambio clave respecto al script original
    --port          $Port `
    --mlock
```

Ejecutar:

```powershell
.\launch-qwen3-9b-lab.ps1 -Context 64k
```

### Regla de Firewall en Windows

```powershell
# PowerShell como administrador
New-NetFirewallRule `
  -DisplayName "llama-server lab" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8080 `
  -Action Allow `
  -Profile Private
```

### Verificar desde la VM

```bash
curl http://192.168.x.1:8080/v1/models
# Debe devolver JSON con el modelo cargado
```

---

## Paso 2 — Ubuntu VM: instalación base

> **⚠️ Python 3.14+**: si tu Ubuntu trae Python 3.14 o superior, muchas dependencias
> de LiteLLM (extensiones C) no tienen wheels precompilados para esa versión y fallarán
> al instalar. Instala Python 3.13 desde el PPA deadsnakes antes de continuar:
>
> ```bash
> sudo add-apt-repository ppa:deadsnakes/ppa
> sudo apt update
> sudo apt install -y python3.13 python3.13-venv python3.13-dev
> ```
>
> Luego sustituye `python3` por `python3.13` en los comandos de venv de este paso.
> Si tienes Python 3.12 o 3.13 de serie, puedes ignorar este bloque.

```bash
sudo apt update && sudo apt install -y \
  python3-pip python3-venv nginx curl wget

# Entorno virtual para LiteLLM
python3 -m venv /opt/litellm-venv   # usa python3.13 si aplica la advertencia anterior
source /opt/litellm-venv/bin/activate
pip install "litellm[proxy]" prometheus-client
```

---

## Paso 3 — Ubuntu VM: configurar LiteLLM

```bash
sudo mkdir -p /opt/litellm
sudo tee /opt/litellm/config.yaml << 'EOF'
model_list:
  - model_name: qwen3-9b
    litellm_params:
      model: openai/Qwen3.5-9B-Q8_0
      api_base: http://192.168.x.1:8080/v1   # <-- IP del host Windows
      api_key: "not-needed"
      timeout: 300

router_settings:
  routing_strategy: simple-shuffle
  num_retries: 2

litellm_settings:
  drop_params: true
  request_timeout: 300
  success_callback: ["prometheus"]   # activa metricas Prometheus
  failure_callback: ["prometheus"]

general_settings:
  master_key: "sk-lab-master-2024"
EOF
```

### Servicio systemd para LiteLLM

```bash
sudo tee /etc/systemd/system/litellm.service << 'EOF'
[Unit]
Description=LiteLLM Proxy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/litellm
Environment="PATH=/opt/litellm-venv/bin:/usr/bin:/bin"
ExecStart=/opt/litellm-venv/bin/litellm \
    --config /opt/litellm/config.yaml \
    --port 4000
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now litellm
sudo journalctl -fu litellm   # observar logs
```

### Verificar LiteLLM

```bash
# Listar modelos disponibles
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer sk-lab-master-2024"

# Test de inferencia
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-lab-master-2024" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-9b",
    "messages": [{"role": "user", "content": "di hola en una palabra"}],
    "max_tokens": 10
  }'

# Metricas Prometheus (deben aparecer tras la primera peticion)
curl http://localhost:4000/metrics
```

---

## Paso 4 — Ubuntu VM: nginx con TLS autofirmado

### Generar certificado

```bash
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
  -keyout /etc/ssl/private/llm-lab.key \
  -out /etc/ssl/certs/llm-lab.crt \
  -subj "/CN=llm-lab.local/O=Lab/C=ES" \
  -addext "subjectAltName=DNS:llm-lab.local,IP:192.168.x.2"
  # sustituye 192.168.x.2 por la IP de tu VM Ubuntu
```

### Configuracion nginx

```bash
sudo tee /etc/nginx/sites-available/litellm << 'EOF'
upstream litellm_backend {
    server 127.0.0.1:4000;
    keepalive 16;
}

server {
    listen 443 ssl;
    server_name llm-lab.local;

    ssl_certificate     /etc/ssl/certs/llm-lab.crt;
    ssl_certificate_key /etc/ssl/private/llm-lab.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location / {
        proxy_pass         http://litellm_backend;
        proxy_set_header   Host $host;
        proxy_read_timeout 300s;
        proxy_buffering    off;   # necesario para streaming SSE
    }
}

server {
    listen 80;
    server_name llm-lab.local;
    return 301 https://$host$request_uri;
}
EOF

sudo ln -s /etc/nginx/sites-available/litellm /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### Verificar HTTPS

```bash
# Desde la VM (ignorando certificado autofirmado con -k)
curl -k https://localhost/v1/models \
  -H "Authorization: Bearer sk-lab-master-2024"

# Desde Windows (PowerShell), añadiendo la IP de la VM:
# Invoke-RestMethod -Uri "https://192.168.x.2/v1/models" -SkipCertificateCheck `
#   -Headers @{"Authorization"="Bearer sk-lab-master-2024"}
```

---

## Paso 5 — Ubuntu VM: Prometheus

### Instalar Prometheus

```bash
# Descargar Prometheus
PROM_VERSION="2.51.2"
wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
tar xf prometheus-${PROM_VERSION}.linux-amd64.tar.gz
sudo mv prometheus-${PROM_VERSION}.linux-amd64 /opt/prometheus
sudo useradd -r -s /bin/false prometheus
sudo chown -R prometheus:prometheus /opt/prometheus
```

### Configuracion prometheus.yml

```bash
sudo tee /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "litellm"
    static_configs:
      - targets: ["localhost:4000"]
    metrics_path: "/metrics"
    scrape_interval: 10s

  - job_name: "node"
    static_configs:
      - targets: ["localhost:9100"]   # node_exporter (paso opcional)
EOF
```

### Servicio systemd

```bash
sudo tee /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/opt/prometheus/prometheus \
    --config.file=/opt/prometheus/prometheus.yml \
    --storage.tsdb.path=/opt/prometheus/data \
    --storage.tsdb.retention.time=7d \
    --web.listen-address=0.0.0.0:9090
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
```

### Verificar Prometheus

```bash
# Interfaz web
curl http://localhost:9090/-/healthy

# Ver metricas de LiteLLM recogidas
curl -s 'http://localhost:9090/api/v1/query?query=litellm_request_total' | python3 -m json.tool
```

Accesible en el navegador de Windows en: `http://192.168.x.2:9090`

---

## Paso 6 — Ubuntu VM: Grafana

### Instalar Grafana

```bash
# apt-key fue eliminado en Ubuntu 24.04+; usar keyrings en su lugar
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | \
  gpg --dearmor | \
  sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
  sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update && sudo apt install -y grafana
sudo systemctl enable --now grafana-server
```

### Configurar datasource Prometheus (via API)

```bash
# Esperar a que Grafana arranque
sleep 5

curl -s -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "isDefault": true
  }'
```

### Dashboard LiteLLM

Importar el dashboard oficial de LiteLLM desde Grafana:

```bash
curl -s -X POST http://admin:admin@localhost:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {"id": null, "title": "LiteLLM Overview"},
    "folderId": 0,
    "overwrite": true,
    "inputs": [{"name": "DS_PROMETHEUS", "type": "datasource", "pluginId": "prometheus", "value": "Prometheus"}]
  }'
```

O manualmente: Grafana UI → Dashboards → Import → ID **`20699`** (dashboard LiteLLM de la comunidad).

Grafana accesible desde Windows en: `http://192.168.x.2:3000`
Credenciales iniciales: `admin / admin` (cambia en el primer login).

---

## Paso 7 — Verificacion end-to-end

Desde PowerShell en Windows:

```powershell
# A traves de nginx HTTPS (certificado autofirmado, -SkipCertificateCheck)
$headers = @{
    "Authorization" = "Bearer sk-lab-master-2024"
    "Content-Type"  = "application/json"
}
$body = '{"model":"qwen3-9b","messages":[{"role":"user","content":"hola"}],"max_tokens":20}'

Invoke-RestMethod `
  -Uri "https://192.168.x.2/v1/chat/completions" `
  -Method POST `
  -Headers $headers `
  -Body $body `
  -SkipCertificateCheck
```

Despues de la peticion, comprueba en Prometheus:

```bash
# Numero total de peticiones procesadas
curl -s 'http://localhost:9090/api/v1/query?query=litellm_request_total'

# Latencia media
curl -s 'http://localhost:9090/api/v1/query?query=litellm_llm_api_latency_metric'
```

---

## Resumen de puertos

| Servicio | VM Ubuntu | Accesible desde Windows |
|---|---|---|
| llama-server | Windows :8080 | Solo desde VM → host |
| LiteLLM | :4000 | No (solo nginx lo consume) |
| nginx HTTPS | :443 | `https://192.168.x.2` |
| Prometheus | :9090 | `http://192.168.x.2:9090` |
| Grafana | :3000 | `http://192.168.x.2:3000` |

## Firewall en Ubuntu (si ufw esta activo)

```bash
sudo ufw allow 443/tcp    # nginx HTTPS
sudo ufw allow 9090/tcp   # Prometheus
sudo ufw allow 3000/tcp   # Grafana
sudo ufw status
```

---

Volver al [README](../README.md)
