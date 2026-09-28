# One dashboard per environment, all from the same template
resource "grafana_dashboard" "ladebahn" {
  for_each = toset(var.environments)

  folder      = grafana_folder.ladebahn.uid
  config_json = templatefile("${path.module}/dashboards/ladebahn.json.tftpl", { environment = each.key })
}

# Same dashboard, new address: do not destroy and recreate it
moved {
  from = grafana_dashboard.ladebahn
  to   = grafana_dashboard.ladebahn["local"]
}
