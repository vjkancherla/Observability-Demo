# Observability Stack Verification Checklist

## ⚠️ Prerequisites: Port Forwarding (REQUIRED)

**These port-forwards MUST be active before running any verification commands. Without them, none of the API queries will work.**

```bash
# Start all port-forwards (run in background with output suppressed)
kubectl port-forward -n observability svc/dev-grafana 3000:80 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/dev-prometheus-kube-promet-prometheus 9090:9090 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/dev-prometheus-kube-promet-alertmanager 9093:9093 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/prometheus-pushgateway 9091:9091 >/dev/null 2>&1 &
```

### Port Forward Summary

| Service | Local Port | Service Port | URL |
|---------|-----------|--------------|-----|
| Grafana | 3000 | 80 | http://localhost:3000 |
| Prometheus | 9090 | 9090 | http://localhost:9090 |
| Alertmanager | 9093 | 9093 | http://localhost:9093 |
| Pushgateway | 9091 | 9091 | http://localhost:9091 |

### Verify Port Forwards are Active
```bash
# Check port-forward processes
ps aux | grep "kubectl port-forward"

# Or check listening ports
lsof -i :3000,9090,9091,9093
```

### Stop All Port Forwards
```bash
pkill -f "kubectl port-forward"
```

**Note:** Port-forwards are automatically started by `deploy.sh` script. If they fail, manually restart them.

---

## 1. Verify Data Flow: CronJob → Pushgateway

### Check CronJob Execution
```bash
# List recent jobs (successful and failed)
kubectl get jobs -n my-demo -l app=request-sender-conditional --sort-by=.metadata.creationTimestamp

# Get most recent failed job
kubectl get jobs -n my-demo -l app=request-sender-conditional \
  -o json | jq -r '.items[] | select(.status.failed == 1) | .metadata.name' | tail -1
```

### Extract Correlation ID
```bash
FAILED_JOB="<job-name>"
kubectl logs -n my-demo -l job-name=$FAILED_JOB | grep "correlation ID"
```

### Verify Pushgateway Has Metrics
```bash
CORRELATION_ID="<your-correlation-id>"
curl -s http://localhost:9091/metrics | grep "$CORRELATION_ID"
```

**Expected:** All metrics (`cronjob_request_info`, `cronjob_request_duration_seconds`, etc.) with correlation_id label

---

## 2. Verify Prometheus is Scraping Pushgateway

### Check Prometheus Targets
```bash
# List all active targets
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Specifically check for Pushgateway
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job | contains("pushgateway"))'
```

**Expected:** Pushgateway target with `"health": "up"`

### If Pushgateway Target is Missing

**Check ServiceMonitor exists:**
```bash
kubectl get servicemonitor -n observability
```

**Verify ServiceMonitor labels:**
```bash
kubectl get servicemonitor -n observability prometheus-pushgateway -o yaml | grep -A 5 "labels:"
```

**Check what Prometheus expects:**
```bash
kubectl get prometheus -n observability dev-prometheus-kube-promet-prometheus -o yaml | grep -A 10 serviceMonitorSelector
```

**Critical:** ServiceMonitor must have labels that match Prometheus's `serviceMonitorSelector`. Typically requires `release: <helm-release-name>`.

---

## 3. Verify Prometheus Has Scraped Metrics

### Query Prometheus for Specific Correlation ID
```bash
CORRELATION_ID="<your-correlation-id>"
curl -s --data-urlencode "query=cronjob_request_info{correlation_id=\"$CORRELATION_ID\"}" \
  http://localhost:9090/api/v1/query | jq .
```

**Expected:** `"status": "success"` with metric results containing all labels (status, response_code, job_type, etc.)

### Check General Metrics Availability
```bash
# Check if ANY cronjob metrics exist
curl -s --data-urlencode 'query=cronjob_request_info' \
  http://localhost:9090/api/v1/query | jq '.data.result | length'
```

---

## 4. Verify PrometheusRule is Loaded

### List All Alert Rule Groups
```bash
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'
```

**Expected:** Your custom rule group name (e.g., `cronjob-pushgateway-correlation`) in the list

### If Rule Group is Missing

**Check PrometheusRule exists:**
```bash
kubectl get prometheusrule -n observability
```

**Verify PrometheusRule labels:**
```bash
kubectl get prometheusrule -n observability <rule-name> -o yaml | grep -A 5 "labels:"
```

**Check what Prometheus expects:**
```bash
kubectl get prometheus -n observability dev-prometheus-kube-promet-prometheus -o yaml | grep -A 10 ruleSelector
```

**Critical:** PrometheusRule must have labels that match Prometheus's `ruleSelector`. Typically requires `release: <helm-release-name>`.

---

## 5. Verify Alerts are Firing

### Check Alert Details
```bash
# View specific alert rule
curl -s http://localhost:9090/api/v1/rules | \
  jq '.data.groups[] | select(.name == "<your-rule-group-name>")'
```

### Check Active Alerts
```bash
# List all active alerts
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts'

# Check specific alert by name
curl -s http://localhost:9090/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.alertname == "<alert-name>")'

# Check specific alert by correlation ID
curl -s http://localhost:9090/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.correlation_id == "<correlation-id>")'
```

**Expected:** Alert in `"state": "firing"` or `"state": "pending"` with correct labels and annotations

---

## 6. Verify Alertmanager Receives Alerts

### Check Alertmanager API
```bash
# List all alerts in Alertmanager
curl -s http://localhost:9093/api/v2/alerts | jq .

# Check specific correlation ID
curl -s http://localhost:9093/api/v2/alerts | \
  jq '.[] | select(.labels.correlation_id == "<correlation-id>")'
```

---

## Key Configuration Requirements

### ServiceMonitor Requirements
- Must be in correct namespace (or Prometheus must watch all namespaces)
- Must have labels matching Prometheus `serviceMonitorSelector`
- Common required label: `release: <prometheus-helm-release-name>`
- Must have `honorLabels: true` to preserve correlation_id from Pushgateway

### PrometheusRule Requirements
- Must be in correct namespace (or Prometheus must watch all namespaces)
- Must have labels matching Prometheus `ruleSelector`
- Common required label: `release: <prometheus-helm-release-name>`

### AlertmanagerConfig Requirements
- Must have labels matching Alertmanager's selector
- Common required label: `alertmanagerConfig: <selector-value>`

---

## Troubleshooting Tips

1. **Always check label selectors first** - Most discovery issues are due to label mismatches
2. **Wait 30-60 seconds after changes** - Prometheus/Alertmanager reload configurations periodically
3. **Use `kubectl describe`** - Shows events and status conditions for resources
4. **Check Prometheus logs** - `kubectl logs -n observability <prometheus-pod> prometheus` for errors
5. **Verify network connectivity** - Ensure services can reach each other within the cluster
