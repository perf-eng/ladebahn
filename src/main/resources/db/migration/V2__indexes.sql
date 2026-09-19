-- Spatial index. Target of lab 02 (drop_index).
CREATE INDEX idx_site_location ON site USING GIST (location);

-- Foreign key indexes. Postgres does NOT create these automatically.
CREATE INDEX idx_charge_point_site ON charge_point(site_id);
CREATE INDEX idx_connector_charge_point ON connector(charge_point_id);
