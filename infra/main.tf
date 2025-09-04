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
      node_locations     = ""
      accelerator_count  = 0
      accelerator_type   = ""
    },
    {
      name               = "gpu-pool"
      machine_type       = "n1-standard-4"
      disk_size_gb       = 100
      image_type         = "COS_CONTAINERD"
      preemptible        = true
      initial_node_count = 0
      autoscaling        = true
      min_count          = 0
      max_count          = 1
      auto_repair        = true
      auto_upgrade       = true
      node_locations     = ""
      accelerator_count  = 1
      accelerator_type   = "nvidia-tesla-t4"
    }
  ]

  node_pools_oauth_scopes = {
    all = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  node_pools_labels = merge(
    {
      cpu-pool = { pool = "cpu" }
    },
    {
    gpu-pool = { pool = "gpu", accelerator = "t4" }
    }
  )

  node_pools_tags = merge(
    {
      cpu-pool = ["gke", "cpu"]
    },
    {
      gpu-pool = ["gke", "gpu", "t4"]
    }
  )

  node_pools_taints = {
    gpu-pool = [
      {
        key    = "nvidia.com/gpu"
        value  = "present"
        effect = "NO_SCHEDULE"
      }
    ]
  }

  cluster_resource_labels = {
    env = "demo"
  }
}