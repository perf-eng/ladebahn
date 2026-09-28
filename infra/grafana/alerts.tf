resource "grafana_rule_group" "latency" {
  name             = "ladebahn-latency"
  folder_uid       = grafana_folder.ladebahn.uid
  interval_seconds = 60

  dynamic "rule" {
    for_each = toset(var.environments)

    content {
      name      = "Nearby search p95 too slow (${rule.value})"
      condition = "THRESHOLD"
      for       = "1m"

      no_data_state  = "OK" # no traffic is not an incident
      exec_err_state = "Error"

      labels = {
        service     = "ladebahn"
        environment = rule.value
      }

      annotations = {
        summary          = "p95 of /api/v1/sites/nearby above ${var.p95_threshold_seconds}s for 1 minute (${rule.value})"
        __dashboardUid__ = "ladebahn-${rule.value}"
        __panelId__      = "1"
      }

      # A: the p95 over the last 5 minutes
      data {
        ref_id         = "P95"
        datasource_uid = "grafanacloud-prom"

        relative_time_range {
          from = 600
          to   = 0
        }

        model = jsonencode({
          refId         = "P95"
          expr          = "histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{deployment_environment=\"${rule.value}\", http_route=\"/api/v1/sites/nearby\"}[5m])))"
          instant       = true
          range         = false
          intervalMs    = 1000
          maxDataPoints = 43200
        })
      }

      # B: is it above the threshold?
      data {
        ref_id         = "THRESHOLD"
        datasource_uid = "__expr__"

        relative_time_range {
          from = 0
          to   = 0
        }

        model = jsonencode({
          refId         = "THRESHOLD"
          type          = "threshold"
          expression    = "P95"
          conditions    = [{ evaluator = { type = "gt", params = [var.p95_threshold_seconds] } }]
          datasource    = { type = "__expr__", uid = "__expr__" }
          intervalMs    = 1000
          maxDataPoints = 43200
        })
      }
    }
  }
}
