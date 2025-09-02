module "gke" {
  source     = "terraform-google-modules/kubernetes-engine/google"
  version    = "~> 33.0"

  project_id = var.project_id
  name       = var.cluster_name

  region     = var.region
  regional   = true

  network    = "default"
  subnetwork = "default"

  release_channel = "REGULAR"

  remove_default_node_pool = true

  ip_range_pods     = null
  ip_range_services = null

  identity_namespace = "${var.project_id}.svc.id.goog"

  deletion_protection = false

  node_pools = [
    {
      name               = "cpu-pool"
      machine_type       = "e2-standard-2"
      disk_size_gb       = 50
      image_type         = "COS_CONTAINERD"
      preemptible        = true
      initial_node_count = 1
      autoscaling        = true
      min_count          = 0
      max_count          = 2
      auto_repair        = true
      auto_upgrade       = true
    }
  ]

  node_pools_oauth_scopes = {
    all = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  node_pools_labels = {
    cpu-pool = { pool = "cpu" }
  }

  node_pools_tags = {
    cpu-pool = ["gke", "cpu"]
  }

  cluster_resource_labels = {
    env = "demo"
  }
}