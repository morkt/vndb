
CREATE TABLE quotes (
  vid integer NOT NULL REFERENCES vn (id),
  quote varchar(250) NOT NULL,
  PRIMARY KEY(vid, quote)
) WITHOUT OIDS;

