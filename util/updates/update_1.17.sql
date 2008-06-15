
-- Add GTIN column
ALTER TABLE releases_rev ADD COLUMN gtin bigint NOT NULL DEFAULT 0;


-- Permanently delete the CISV link and add links to encubed and renai.us
ALTER TABLE vn_rev DROP COLUMN l_cisv;
ALTER TABLE vn_rev ADD COLUMN l_encubed varchar(100) NOT NULL DEFAULT '';
ALTER TABLE vn_rev ADD COLUMN l_renai varchar(100) NOT NULL DEFAULT '';

