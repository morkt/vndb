
-- some random VN quotes
CREATE TABLE quotes (
  vid integer NOT NULL REFERENCES vn (id),
  quote varchar(250) NOT NULL,
  PRIMARY KEY(vid, quote)
) WITHOUT OIDS;


-- catalog numbers for releases
ALTER TABLE releases_rev ADD COLUMN catalog varchar(50) NOT NULL DEFAULT '';


-- aliases field for producers
ALTER TABLE producers_rev ADD COLUMN alias varchar(500) NOT NULL DEFAULT '';

