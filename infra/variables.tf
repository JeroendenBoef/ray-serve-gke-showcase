variable "project_id" {
  type    = string
  default = "ray-serve-gke-showcase-1122"
}

variable "region" {
  type    = string
  default = "europe-west4"
}

variable "zone" {
  type    = string
  default = "europe-west4-a"
}

variable "cluster_name" {
  type    = string
  default = "ray-serve-gke"
}
