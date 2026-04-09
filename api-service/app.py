import os
import uuid
from datetime import datetime, timezone

from flask import Flask, request, jsonify
from google.cloud import firestore

app = Flask(__name__)
db = firestore.Client()
COLLECTION = os.getenv("FIRESTORE_COLLECTION", "pi_jobs")

@app.route("/estimate_pi", methods=["POST"])
def estimate_pi():
    data = request.get_json(silent=True) or {}
    total_points = data.get("total_points")

    app.logger.info(f"Received estimate request with payload: {data}")

    if not isinstance(total_points, int) or total_points <= 0:
        return jsonify({"error": "total_points must be a positive integer"}), 400

    job_id = str(uuid.uuid4())
    job_doc = {
        "job_id": job_id,
        "total_points": total_points,
        "status": "queued",
        "created_at": datetime.now(timezone.utc).isoformat()
    }

    app.logger.info(f"Creating Firestore job {job_id}")
    db.collection(COLLECTION).document(job_id).set(job_doc)

    app.logger.info(f"Queued job {job_id} for {total_points} points")

    return jsonify({
        "job_id": job_id,
        "status": "accepted"
    }), 202

@app.get("/health")
def health():
    return "ok", 200
