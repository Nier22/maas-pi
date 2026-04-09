import os
import json
import random
from datetime import datetime, timezone

from flask import Flask, request, jsonify
from google.cloud import firestore

app = Flask(__name__)
db = firestore.Client()
COLLECTION = os.getenv("FIRESTORE_COLLECTION", "pi_jobs")

def estimate_pi(n: int) -> float:
    inside_circle = 0
    for _ in range(n):
        x, y = random.uniform(-1, 1), random.uniform(-1, 1)
        if x * x + y * y <= 1:
            inside_circle += 1
    return (4 * inside_circle) / n

@app.post("/")
def handle_event():
    envelope = request.get_json(silent=True) or {}
    app.logger.info(f"Received Eventarc event: {json.dumps(envelope)[:1000]}")

    # Firestore direct events include changed document info in CloudEvent payload.
    # The exact payload can vary by event type, so we read the document name if present.
    value = envelope.get("value", {})
    name = value.get("name", "")

    if not name:
        return jsonify({"message": "No document path found"}), 400

    # name format resembles:
    # projects/{project}/databases/{database}/documents/{collection}/{docId}
    parts = name.split("/documents/")
    if len(parts) != 2:
        return jsonify({"message": "Invalid document name"}), 400

    doc_path = parts[1]
    doc_ref = db.document(doc_path)
    snapshot = doc_ref.get()

    if not snapshot.exists:
        return jsonify({"message": "Document not found"}), 404

    job = snapshot.to_dict()
    total_points = int(job["total_points"])
    job_id = job["job_id"]

    app.logger.info(f"Starting job {job_id} with {total_points} points")

    pi_estimate = estimate_pi(total_points)

    doc_ref.update({
        "status": "done",
        "pi_estimate": pi_estimate,
        "completed_at": datetime.now(timezone.utc).isoformat()
    })

    app.logger.info(f"Completed job {job_id}, pi={pi_estimate}")

    return jsonify({"message": "processed"}), 200

@app.get("/health")
def health():
    return "ok", 200