variable "project_id" {
  type    = string
}

variable "region" {
  type    = string
}

variable "zone" {
  type    = string
}

variable "cluster_name" {
  type    = string
  default = "ray-serve-gke"
}
