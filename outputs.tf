output "gateway_url" {
  value = google_api_gateway_gateway.maas_gateway.default_hostname
}

output "api_service_url" {
  value = google_cloud_run_v2_service.api_service.uri
}

output "sim_service_url" {
  value = google_cloud_run_v2_service.sim_service.uri
}