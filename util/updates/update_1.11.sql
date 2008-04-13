
UPDATE vn_rev SET categories = categories << 6;

ALTER TABLE vn_rev ADD COLUMN l_vnn integer NOT NULL DEFAULT 0;
