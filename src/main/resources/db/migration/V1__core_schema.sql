CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE operator (
  id      BIGSERIAL PRIMARY KEY,
  name    TEXT NOT NULL,
  country CHAR(2) NOT NULL
);

CREATE TABLE site (
  id          BIGSERIAL PRIMARY KEY,
  operator_id BIGINT NOT NULL REFERENCES operator(id),
  name        TEXT NOT NULL,
  street      TEXT,
  city        TEXT,
  postcode    TEXT,
  location    geography(Point, 4326) NOT NULL,
  popularity  DOUBLE PRECISION NOT NULL DEFAULT 1.0
);

CREATE TABLE charge_point (
  id        BIGSERIAL PRIMARY KEY,
  site_id   BIGINT NOT NULL REFERENCES site(id),
  serial    TEXT NOT NULL UNIQUE,
  vendor    TEXT,
  model     TEXT,
  firmware  TEXT,
  status    TEXT NOT NULL,
  last_seen TIMESTAMPTZ
);

CREATE TABLE connector (
  id              BIGSERIAL PRIMARY KEY,
  charge_point_id BIGINT NOT NULL REFERENCES charge_point(id),
  ordinal         INT NOT NULL,
  type            TEXT NOT NULL,
  max_kw          NUMERIC(6,2) NOT NULL,
  status          TEXT NOT NULL,
  version         BIGINT NOT NULL DEFAULT 0
);
