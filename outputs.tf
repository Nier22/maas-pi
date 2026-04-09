output "gateway_url" {
  value = "https://${google_api_gateway_gateway.maas_gateway.default_hostname}"
}

output "estimate_pi_endpoint" {
  value = "https://${google_api_gateway_gateway.maas_gateway.default_hostname}/estimate_pi"
}

output "api_service_url" {
  value = google_cloud_run_v2_service.api_service.uri
}

output "sim_service_url" {
  value = google_cloud_run_v2_service.sim_service.uri
}
