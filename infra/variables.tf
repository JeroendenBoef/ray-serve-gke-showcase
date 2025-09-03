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

variable "kms_key_ring" { 
  type    = string
}

variable "kms_crypto_key" {
  type    = string
  }
