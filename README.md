# 🚀 Minimal Observability Stack with Tracing App

This project provides a **self-contained observability playground** on Kubernetes using:

- **k3d** (lightweight k3s-based cluster)
- **Prometheus** (metrics)
- **Loki + Promtail** (logs)
- **Grafana** (dashboards)
- **Tracing App** (sample webapp with structured JSON logging + correlation IDs)

---

## 🛠️ Requirements

Make sure you have the following installed:

- [k3d](https://k3d.io/)  
- [kubectl](https://kubernetes.io/docs/tasks/tools/)  
- [helm](https://helm.sh/docs/intro/install/)  

---

## 📦 Deployment

Spin up the full stack with a single command:

```bash
./deploy.sh
```
This will:

1. Create a local **k3d** cluster.  
2. Add required **Helm repositories**.  
3. Deploy Prometheus, Loki, Promtail, Grafana, and the Tracing App.  
4. Start port-forwards for Grafana.  

🧹 Cleanup
Tear everything down:

```bash
./cleanup.sh
```
This will stop port-forwards and delete the k3d cluster.

## 📊 Grafana

- URL: http://localhost:3000  
- Username: `admin`  
- Password: `admin` (configurable in `values/grafana.yaml`)  

### Preconfigured Datasources

- Prometheus → `http://dev-prometheus-kube-promet-prometheus.observability.svc.cluster.local:9090`  
- Loki → `http://dev-loki.observability.svc.cluster.local:3100`  

### Preloaded Dashboards

- **Logs** (`uid: simple-logs`)  
  - Queries `{app="tracing-app"}`  
  - Provides a textbox variable `correlation_id`  
  - Displays logs with labels & timestamps  

---

## 📋 Features

- End-to-end observability with **metrics, logs, and dashboards**  
- **Tracing App** with structured JSON logging, request ID + correlation ID headers  
- Endpoints: `/`, `/health`, `/metrics`, `/trace`  
- CronJob generates demo traffic with correlation IDs  

---

## 📂 Project Structure

```
deploy.sh # End-to-end deployment script
cleanup.sh # Teardown script
values/ # Helm values for Prometheus, Loki, Promtail, Grafana
tracing-app-helm-chart/ # Helm chart for the tracing demo app
```

---

## 🔍 Example Flow

1. CronJob sends a request every minute with a unique `correlation_id`.  
2. Nginx logs the request in JSON format.  
3. Promtail collects logs and pushes them to Loki.  
4. Grafana dashboard lets you query logs filtered by `correlation_id`.  

---

##  ⚡ Quick Demo
```
./deploy.sh

# Open Grafana at http://localhost:3000

Then open the Logs dashboard in Grafana and filter by the emitted correlation_id.

1. The CronJob automatically sends requests to the Tracing App with unique `correlation_id` headers.  
2. Logs are collected by Promtail → stored in Loki → visualized in Grafana.  
3. Open the **Logs dashboard** and filter by `correlation_id` to trace requests end-to-end.  
```