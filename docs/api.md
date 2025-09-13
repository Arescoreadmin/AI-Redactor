# API (MVP)
- POST /v1/jobs { type: doc|audio|video, org_id? } -> { id, status }
- GET /v1/jobs/{id}
- POST /v1/review/{id}/approve

Flow: create job -> orchestrator sets running -> worker proposes -> orchestrator marks waiting_review -> approve -> packager completes.
