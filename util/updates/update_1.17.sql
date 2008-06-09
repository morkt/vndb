
-- Add GTIN column
ALTER TABLE releases_rev ADD COLUMN gtin bigint NOT NULL DEFAULT 0;


