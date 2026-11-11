CREATE TABLE urls (
  code        VARCHAR(64) PRIMARY KEY,
  long_url    TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
