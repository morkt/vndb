
-- remove the NOT NULL from rr.minage and use -1 when unknown
UPDATE releases_rev SET minage = -1 WHERE minage IS NULL;
ALTER TABLE releases_rev ALTER COLUMN minage SET DEFAULT -1;
ALTER TABLE releases_rev ALTER COLUMN minage DROP NOT NULL;

