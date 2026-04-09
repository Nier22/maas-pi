terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  api_service_name = "maas-api-service"
  sim_service_name = "maas-sim-service"
  db_name          = "(default)"
  collection       = "pi_jobs"
}

# Enable required services
resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "apigateway.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicecontrol.googleapis.com",
    "firestore.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com"
  ])

  service            = each.key
  disable_on_destroy = false
}

# Firestore database
resource "google_firestore_database" "database" {
  project     = var.project_id
  name        = local.db_name
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.services]
}

# Service accounts
resource "google_service_account" "api_sa" {
  account_id   = "maas-api-sa"
  display_name = "MaaS API Service Account"
}

resource "google_service_account" "sim_sa" {
  account_id   = "maas-sim-sa"
  display_name = "MaaS Simulation Service Account"
}

resource "google_service_account" "eventarc_sa" {
  account_id   = "maas-eventarc-sa"
  display_name = "MaaS Eventarc Trigger Service Account"
}

# Firestore access
resource "google_project_iam_member" "api_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "sim_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.sim_sa.email}"
}

# Eventarc permissions
resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

# Cloud Run API service
resource "google_cloud_run_v2_service" "api_service" {
  name     = local.api_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.api_sa.email
    timeout         = "60s"

    containers {
      image = var.api_image

      env {
        name  = "FIRESTORE_COLLECTION"
        value = local.collection
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }

  depends_on = [google_project_service.services]
}

# Allow API Gateway to invoke api_service
resource "google_cloud_run_service_iam_member" "api_public" {
  location = var.region
  service  = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Run simulation service
resource "google_cloud_run_v2_service" "sim_service" {
  name     = local.sim_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.sim_sa.email
    timeout         = "3600s"

    containers {
      image = var.sim_image

      env {
        name  = "FIRESTORE_COLLECTION"
        value = local.collection
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 50
    }
  }

  depends_on = [google_project_service.services]
}

# Eventarc trigger: Firestore document created -> sim_service
resource "google_eventarc_trigger" "firestore_created_trigger" {
  name     = "maas-firestore-created-trigger"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.firestore.document.v1.created"
  }

  matching_criteria {
    attribute = "database"
    value     = local.db_name
  }

  matching_criteria {
    attribute = "namespace"
    value     = "(default)"
  }

  matching_criteria {
    attribute = "document"
    value     = "${local.collection}/{docId}"
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.sim_service.name
      region  = var.region
      path    = "/"
    }
  }

  service_account = google_service_account.eventarc_sa.email

  depends_on = [
    google_project_service.services,
    google_firestore_database.database,
    google_cloud_run_v2_service.sim_service
  ]
}

# API Gateway config file
resource "google_api_gateway_api" "maas_api" {
  api_id = "maas-api"
  depends_on = [google_project_service.services]
}

resource "google_api_gateway_api_config" "maas_api_config" {
  api      = google_api_gateway_api.maas_api.api_id
  api_config_id = "maas-api-config"

  openapi_documents {
    document {
      path     = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi.yaml.tpl", {
        backend_url = google_cloud_run_v2_service.api_service.uri
      }))
    }
  }

  depends_on = [google_cloud_run_v2_service.api_service]
}

resource "google_api_gateway_gateway" "maas_gateway" {
  gateway_id = "maas-gateway"
  api_config = google_api_gateway_api_config.maas_api_config.id
  region     = var.region
}
