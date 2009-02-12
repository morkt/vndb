
-- some random VN quotes
CREATE TABLE quotes (
  vid integer NOT NULL REFERENCES vn (id),
  quote varchar(250) NOT NULL,
  PRIMARY KEY(vid, quote)
) WITHOUT OIDS;


-- catalog numbers for releases
ALTER TABLE releases_rev ADD COLUMN catalog varchar(50) NOT NULL DEFAULT '';
