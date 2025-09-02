output "cluster_name" {
  value       = module.gke.name
  description = "GKE cluster name"
}

output "region" {
  value       = module.gke.location
  description = "Cluster region"
}

output "project_id" {
  value       = var.project_id
}
