variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "firestore_location" {
  type    = string
  default = "us-central"
}

variable "api_image" {
  type = string
}

variable "sim_image" {
  type = string
}