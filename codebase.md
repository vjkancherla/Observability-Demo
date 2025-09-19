# cleanup.sh

```sh
#!/bin/bash

echo "🧹 Cleaning up..."

pkill -f "kubectl port-forward" 2>/dev/null || true
k3d cluster delete mycluster 2>/dev/null || true

echo "✅ Done!"
```

# deploy.sh

```sh
#!/bin/bash
set -e

echo "Creating k3d cluster..."
k3d cluster delete mycluster 2>/dev/null || true
k3d cluster create mycluster --agents 1 --wait
echo "   Cluster ready"

echo "Adding helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null
echo "   Repositories updated"

echo "Creating namespaces..."
kubectl create namespace observability 2>/dev/null || true
kubectl create namespace my-demo 2>/dev/null || true
echo "   Namespaces observability and my-demo created"

wait_for_release() {
  release=$1
  namespace=$2
  echo "   Waiting for pods of release '$release' in namespace '$namespace' to be ready..."
  kubectl rollout status -n "$namespace" deployment -l app.kubernetes.io/instance=$release --timeout=5m || true
  kubectl rollout status -n "$namespace" statefulset -l app.kubernetes.io/instance=$release --timeout=5m || true
}

echo "Deploying Prometheus (v72.5.1)..."
helm upgrade --install dev-prometheus prometheus-community/kube-prometheus-stack \
  --version 72.5.1 --namespace observability -f values/prometheus.yaml --wait --timeout=5m
wait_for_release dev-prometheus observability
echo "   Prometheus deployed"

echo "Deploying Loki (6.40.0)..."
helm upgrade --install dev-loki grafana/loki \
  --version 6.40.0 --namespace observability -f values/loki.yaml --wait --timeout=5m
wait_for_release dev-loki observability
echo "   Loki deployed"

echo "Deploying Promtail (6.17.0)..."
helm upgrade --install dev-promtail grafana/promtail \
  --version 6.17.0 --namespace observability -f values/promtail.yaml --wait --timeout=5m
wait_for_release dev-promtail observability
echo "   Promtail deployed"

echo "Deploying Grafana (v9.0.0)..."
helm upgrade --install dev-grafana grafana/grafana \
  --version 9.0.0 --namespace observability -f values/grafana.yaml --wait --timeout=5m
wait_for_release dev-grafana observability
echo "   Grafana deployed"

echo "Deploying Tracing App..."
helm upgrade --install dev-tracing ./tracing-app-helm-chart \
  --namespace my-demo --wait --timeout=5m
wait_for_release dev-tracing my-demo
echo "   Tracing app deployed"

# Update the port-forward section
echo "Starting port-forwards..."
kubectl port-forward -n observability svc/dev-grafana 3000:80 >/dev/null 2>&1 &
echo "   Port-forwards started (background)"

echo ""
echo "Deployment complete!"
echo "   Grafana: http://localhost:3000 (admin/admin)"
echo "   Stop: ./cleanup.sh"

```

# README.md

```md
# Minimal Observability Stack

**Requirements:** k3d, kubectl, helm

## Usage

\`\`\`bash
./deploy.sh    # Deploy everything
./cleanup.sh   # Remove everything
\`\`\`

**Grafana:** http://localhost:3000 (admin/admin)

That's it.
```

# tracing-app-helm-chart/Chart.yaml

```yaml
apiVersion: v2
name: tracing-app
description: A Helm chart for request tracing with structured JSON logging
type: application
version: 0.1.0
appVersion: "1.0"
keywords:
  - tracing
  - logging
  - observability
  - nginx
  - grafana
  - loki
home: https://github.com/your-org/tracing-app
maintainers:
  - name: Your Name
    email: your.email@example.com
```

# tracing-app-helm-chart/files/index.html

```html
<!DOCTYPE html>
<html>
<head>
    <title>Tracing App</title>
</head>
<body>
    <h1>Request Tracing Service</h1>
    <p>Status: Running</p>
    <p>Service: tracing-webapp</p>
</body>
</html>
```

# tracing-app-helm-chart/files/nginx.conf

```conf
# JSON log format for Grafana/Loki compatibility
log_format json_combined escape=json
'{'
  '"timestamp":"$time_iso8601",'
  '"level":"info",'
  '"service":"tracing-webapp",'
  '"pod_name":"$hostname",'
  '"method":"$request_method",'
  '"path":"$uri",'
  '"query_string":"$args",'
  '"status":$status,'
  '"request_time":$request_time,'
  '"response_size":$body_bytes_sent,'
  '"remote_addr":"$remote_addr",'
  '"user_agent":"$http_user_agent",'
  '"referer":"$http_referer",'
  '"correlation_id":"$http_correlation_id",'
  '"x_forwarded_for":"$http_x_forwarded_for",'
  '"request_id":"$request_id",'
  '"upstream_response_time":"$upstream_response_time",'
  '"scheme":"$scheme",'
  '"host":"$host"'
'}';

server {
    listen 80;
    server_name localhost;
    
    # Use JSON logging for all requests
    access_log /var/log/nginx/access.log json_combined;
    error_log /var/log/nginx/error.log warn;
    
    # Generate unique request ID for each request
    add_header X-Request-ID $request_id always;
    
    location / {
        root /usr/share/nginx/html;
        index index.html;
        
        # Add correlation ID to response headers
        add_header X-Correlation-ID $http_correlation_id always;
        add_header X-Service "tracing-webapp" always;
        add_header X-Pod-Name $hostname always;
    }
    
    # Health check endpoint (no logging to reduce noise)
    location /health {
        access_log off;
        return 200 '{"status":"healthy","timestamp":"$time_iso8601","pod":"$hostname","service":"tracing-webapp"}\n';
        add_header Content-Type application/json;
    }
    
    # Metrics endpoint
    location /metrics {
        return 200 '{"service":"tracing-webapp","pod":"$hostname","timestamp":"$time_iso8601","status":"running"}\n';
        add_header Content-Type application/json;
    }
    
    # Trace endpoint for testing
    location /trace {
        return 200 '{"message":"Trace endpoint accessed","correlation_id":"$http_correlation_id","timestamp":"$time_iso8601","pod":"$hostname"}\n';
        add_header Content-Type application/json;
    }
}
```

# tracing-app-helm-chart/templates/_helpers.tpl

```tpl
{{/*
Expand the name of the chart.
*/}}
{{- define "tracing-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tracing-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tracing-app.labels" -}}
helm.sh/chart: {{ include "tracing-app.chart" . }}
app.kubernetes.io/name: {{ include "tracing-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tracing-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tracing-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

# tracing-app-helm-chart/templates/configmap-html.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.webapp.name }}-html-config
  labels:
    app: {{ .Values.webapp.name }}
    {{- include "tracing-app.labels" . | nindent 4 }}
data:
  index.html: |
    {{ .Files.Get "config/index.html" | nindent 4 }}
```

# tracing-app-helm-chart/templates/configmap-nginx.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.webapp.name }}-nginx-config
  labels:
    app: {{ .Values.webapp.name }}
    {{- include "tracing-app.labels" . | nindent 4 }}
data:
  default.conf: |
    {{ .Files.Get "files/nginx.conf" | nindent 4 }}
```

# tracing-app-helm-chart/templates/cronjob.yaml

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ .Values.cronjob.name }}-cronjob
  labels:
    app: {{ .Values.cronjob.name }}
    {{- include "tracing-app.labels" . | nindent 4 }}
spec:
  schedule: {{ .Values.cronjob.schedule | quote }}
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: {{ .Values.cronjob.name }}
            image: "{{ .Values.cronjob.image.repository }}:{{ .Values.cronjob.image.tag }}"
            command:
            - /bin/sh
            - -c
            - |
              # Generate correlation ID
              CORRELATION_ID="req-$(date +%Y%m%d-%H%M%S)-$(shuf -i 10000-99999 -n 1)"
              
              echo "🚀 Sending request with correlation ID: $CORRELATION_ID"
              
              # Make request to webapp
              curl -H "correlation-id: $CORRELATION_ID" \
                   -H "User-Agent: TracingBot/1.0" \
                   -s -o /dev/null \
                   http://{{ .Values.webapp.name }}-service/
              
              echo "✅ Request completed"
          restartPolicy: OnFailure
```

# tracing-app-helm-chart/templates/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.webapp.name }}-deployment
  labels:
    app: {{ .Values.webapp.name }}
    {{- include "tracing-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.webapp.replicas }}
  selector:
    matchLabels:
      app: {{ .Values.webapp.name }}
      {{- include "tracing-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        app: {{ .Values.webapp.name }}
        {{- include "tracing-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Values.webapp.name }}
        image: "{{ .Values.webapp.image.repository }}:{{ .Values.webapp.image.tag }}"
        imagePullPolicy: {{ .Values.webapp.image.pullPolicy }}
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
        - name: html-content
          mountPath: /usr/share/nginx/html
        {{- if .Values.webapp.resources }}
        resources:
          {{- toYaml .Values.webapp.resources | nindent 10 }}
        {{- end }}
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: nginx-config
        configMap:
          name: {{ .Values.webapp.name }}-nginx-config
      - name: html-content
        configMap:
          name: {{ .Values.webapp.name }}-html-config
```

# tracing-app-helm-chart/templates/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.webapp.name }}-service
  labels:
    app: {{ .Values.webapp.name }}
    {{- include "tracing-app.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: {{ .Values.webapp.name }}
    {{- include "tracing-app.selectorLabels" . | nindent 4 }}
```

# tracing-app-helm-chart/values.yaml

```yaml
# Simple values for tracing app
webapp:
  name: webapp
  replicas: 1
  image:
    repository: nginx
    tag: alpine
    pullPolicy: IfNotPresent
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

cronjob:
  name: request-sender
  schedule: "*/1 * * * *"  # Every minute
  image:
    repository: curlimages/curl
    tag: latest
```

# values/grafana.yaml

```yaml
adminPassword: admin

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi

persistence:
  enabled: false

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://dev-prometheus-kube-promet-prometheus.observability.svc.cluster.local:9090
      isDefault: true
    - name: Loki
      type: loki
      uid: loki
      access: proxy
      url: http://dev-loki.observability.svc.cluster.local:3100
      jsonData:
        maxLines: 1000
```

# values/loki.yaml

```yaml
deploymentMode: SingleBinary

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: 'filesystem'
  limits_config:
    retention_period: 24h
    ingestion_rate_mb: 4
    ingestion_burst_size_mb: 6
  schemaConfig:
    configs:
      - from: 2024-04-01
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 200Mi
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      cpu: 200m
      memory: 512Mi

# Explicitly disable SimpleScalable components
write:
  replicas: 0
read:
  replicas: 0  
backend:
  replicas: 0

# Disable memory-hungry caching components
chunksCache:
  enabled: false
resultsCache:
  enabled: false
memcached:
  enabled: false

# Disable other optional components
test:
  enabled: false
monitoring:
  enabled: false
lokiCanary:
  enabled: false
```

# values/prometheus.yaml

```yaml
grafana:
  enabled: false

prometheus:
  prometheusSpec:
    retention: 2h
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          resources:
            requests:
              storage: 200Mi

alertmanager:
  enabled: true
  alertmanagerSpec:
    resources:
      requests:
        cpu: 25m
        memory: 32Mi
      limits:
        cpu: 50m
        memory: 64Mi
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          resources:
            requests:
              storage: 200Mi

nodeExporter:
  enabled: false

grafana:
  enabled: false

kubeStateMetrics:
  enabled: true
```

# values/promtail.yaml

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi

config:
  clients:
    - url: http://dev-loki.observability.svc.cluster.local:3100/loki/api/v1/push

  scrape_configs:
    - job_name: kubernetes-pods
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: namespace
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: pod
        - source_labels: [__meta_kubernetes_pod_label_app]
          action: replace
          target_label: app

      pipeline_stages:
        - json:
            expressions:
              timestamp: timestamp
              level: level
              service: service
              method: method
              path: path
              status: status
              correlation_id: correlation_id
              user_agent: user_agent
              request_time: request_time
              pod_name: pod_name
        - labels:
            service:
            method:
            status:
            correlation_id:
        - timestamp:
            source: timestamp
            format: RFC3339

```

