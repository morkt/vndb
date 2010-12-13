

ALTER TABLE tags_vn ADD COLUMN date timestamptz NOT NULL DEFAULT NOW();

-- this index is essential, quite often sorted on
CREATE INDEX tags_vn_date ON tags_vn (date);

