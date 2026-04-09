# Mass Pi on GCP

This project implements a cloud-native Monte Carlo Pi estimation pipeline on Google Cloud Platform using:

- API Gateway
- Cloud Run receiver service
- Eventarc
- Cloud Run simulator service
- Firestore

The flow is:

`Client -> API Gateway -> Receiver service -> Eventarc via Firestore -> Simulator service -> Firestore`

## Architecture

This repo uses one consistent event-driven design from end to end:

1. A client sends `POST /estimate_pi` through API Gateway.
2. The receiver service validates the request and creates a new job document in Firestore.
3. Eventarc listens for Firestore document creation events.
4. The simulator service is triggered by Eventarc.
5. The simulator runs the Monte Carlo calculation and updates the Firestore document with the result.

This satisfies the assignment requirement for:

- an API gateway
- two services
- an event bridge
- an external datastore

## Repository Structure

- [api-service/app.py](/c:/Users/mogta/Documents/GitHub/mass-pi/api-service/app.py): receiver service that accepts requests and creates jobs
- [api-service/Dockerfile](/c:/Users/mogta/Documents/GitHub/mass-pi/api-service/Dockerfile): container definition for the receiver service
- [api-service/requirements.txt](/c:/Users/mogta/Documents/GitHub/mass-pi/api-service/requirements.txt): Python dependencies for the receiver service
- [sim-service/app.py](/c:/Users/mogta/Documents/GitHub/mass-pi/sim-service/app.py): simulator service triggered by Eventarc
- [sim-service/Dockerfile](/c:/Users/mogta/Documents/GitHub/mass-pi/sim-service/Dockerfile): container definition for the simulator service
- [sim-service/requirements.txt](/c:/Users/mogta/Documents/GitHub/mass-pi/sim-service/requirements.txt): Python dependencies for the simulator service
- [main.tf](/c:/Users/mogta/Documents/GitHub/mass-pi/main.tf): core GCP infrastructure
- [variables.tf](/c:/Users/mogta/Documents/GitHub/mass-pi/variables.tf): Terraform input variables
- [outputs.tf](/c:/Users/mogta/Documents/GitHub/mass-pi/outputs.tf): Terraform outputs
- [openapi.yaml.tpl](/c:/Users/mogta/Documents/GitHub/mass-pi/openapi.yaml.tpl): API Gateway OpenAPI template

## Services

### Receiver Service

Responsibilities:

- expose `POST /estimate_pi`
- read `{"total_points": N}`
- generate a `job_id`
- create a Firestore job document
- return `202 Accepted` immediately

Current Firestore fields created by the receiver:

- `job_id`
- `total_points`
- `status = queued`
- `created_at`

### Simulator Service

Responsibilities:

- receive the job trigger from Eventarc
- look up the Firestore job document
- run the Monte Carlo simulation
- update Firestore with the result

Current Firestore fields written by the simulator:

- `status = processing` while the simulation is running
- `status = done`
- `pi_estimate`
- `completed_at`
- `status = failed` if processing errors

## Recommended Firestore Document Shape

Each job document should include:

- `job_id`
- `total_points`
- `status`
- `created_at`
- `completed_at`
- `pi_estimate`

Recommended statuses:

- `queued`
- `processing`
- `done`
- `failed`

## Prerequisites

Before deployment, make sure these GCP services are enabled:

- Cloud Run
- API Gateway
- Artifact Registry
- Firestore
- Eventarc
- IAM
- Cloud Resource Manager
- Cloud Build
- Logging
- Monitoring

Also make sure:

- the default Firestore database exists
- the Firestore region is chosen once and used consistently
- service accounts have the required IAM roles before testing

## Service Accounts and IAM

Each Cloud Run service should use a dedicated service account.

Receiver service account needs:

- permission to write to Firestore

Simulator service account needs:

- permission to read Firestore
- permission to update Firestore

Eventarc trigger service account needs:

- permission to receive Eventarc events
- permission to invoke the simulator Cloud Run service

## Local Development

Create Dockerfiles and verify both services locally before deploying.

Receiver service example:

```powershell
cd api-service
docker build -t api-service .
docker run --rm -p 8080:8080 api-service
```

Test the receiver:

```powershell
curl -Method POST `
  -Uri http://localhost:8080/estimate_pi `
  -ContentType "application/json" `
  -Body '{"total_points":1000}'
```

Simulator service example:

```powershell
cd sim-service
docker build -t sim-service .
docker run --rm -p 8080:8080 sim-service
```

You should also test the simulator with a representative Eventarc payload before deploying.

## Build and Push Images

Use image names that exactly match the values passed into Terraform.

Example naming pattern:

```text
us-central1-docker.pkg.dev/PROJECT_ID/maas-repo/api-service:latest
us-central1-docker.pkg.dev/PROJECT_ID/maas-repo/sim-service:latest
```

Do not use one set of names in Terraform and a different set during image build and push.

## Terraform

This repo includes:

- [main.tf](/c:/Users/mogta/Documents/GitHub/mass-pi/main.tf)
- [variables.tf](/c:/Users/mogta/Documents/GitHub/mass-pi/variables.tf)
- [outputs.tf](/c:/Users/mogta/Documents/GitHub/mass-pi/outputs.tf)
- [openapi.yaml.tpl](/c:/Users/mogta/Documents/GitHub/mass-pi/openapi.yaml.tpl)

Current input variables:

- `project_id`
- `region`
- `firestore_location`
- `api_image`
- `sim_image`

Current outputs:

- `gateway_url`
- `estimate_pi_endpoint`
- `api_service_url`
- `sim_service_url`

Example apply:

```powershell
terraform init
terraform apply `
  -var="project_id=YOUR_PROJECT_ID" `
  -var="region=us-central1" `
  -var="firestore_location=us-central" `
  -var="api_image=us-central1-docker.pkg.dev/YOUR_PROJECT_ID/maas-repo/api-service:latest" `
  -var="sim_image=us-central1-docker.pkg.dev/YOUR_PROJECT_ID/maas-repo/sim-service:latest"
```

## Correct Deployment Order

Follow this sequence:

1. Write the service code.
2. Build Docker images.
3. Push images to Artifact Registry.
4. Apply Terraform.
5. Verify both Cloud Run services are healthy.
6. Verify the API Gateway endpoint exists.
7. Test one request.
8. Verify background processing.
9. Run 50 concurrent requests.
10. Collect logs and metrics.

## End-to-End Validation

Before load testing, confirm one request works fully.

Expected behavior:

- the API returns `202 Accepted`
- a Firestore job document appears
- Eventarc triggers the simulator
- the Firestore job status changes from `queued` to `done`
- the result is written to Firestore

Example request:

```json
{
  "total_points": 10000000
}
```

## Concurrency Test

Only run the 50-request test after the full pipeline succeeds for a single request.

Verify that:

- all requests return `202`
- Firestore contains all jobs
- job statuses eventually become `done`
- each completed job stores a result

## Logging and Evidence

Collect logs intentionally from both services.

Receiver logs should show:

- request received
- job created
- job queued in Firestore

Simulator logs should show:

- job received
- simulation started
- simulation completed
- Firestore updated

For submission, capture screenshots of:

- API Gateway configuration
- Cloud Run receiver service
- Cloud Run simulator service
- Firestore collection with jobs
- one completed Firestore document
- receiver logs
- simulator logs
- Cloud Run or API Gateway metrics
- 50-concurrent-request test output

## Final Checklist

- choose one event architecture only
- keep code and Terraform consistent
- create Firestore before testing
- set IAM roles before testing
- build images with the exact names Terraform expects
- deploy infrastructure after images exist
- test one request first
- confirm Firestore status changes to `done`
- run 50 concurrent requests only after end-to-end success
- collect logs, metrics, and Firestore screenshots

## Notes

This repository currently follows the Eventarc plus Firestore design:

- the receiver writes jobs to Firestore
- Eventarc listens for Firestore document creation
- the simulator updates the same job document with the result

If you extend this project, keep the application code and Terraform aligned with that same architecture throughout.
