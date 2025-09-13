CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS orgs(
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TYPE job_type AS ENUM ('doc','audio','video');
CREATE TYPE job_status AS ENUM ('queued','running','waiting_review','approved','packaging','completed','failed','blocked_over_cap');
CREATE TABLE IF NOT EXISTS jobs(
  id UUID PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES orgs(id),
  type job_type NOT NULL,
  status job_status NOT NULL DEFAULT 'queued',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS audit_events(
  id BIGSERIAL PRIMARY KEY,
  org_id UUID NOT NULL,
  actor TEXT NOT NULL,
  action TEXT NOT NULL,
  object_ref TEXT NOT NULL,
  payload_digest TEXT,
  prev_hash TEXT NOT NULL,
  this_hash TEXT NOT NULL,
  ts TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
