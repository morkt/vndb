ALTER TABLE users ADD COLUMN pvotes smallint NOT NULL DEFAULT 1;
ALTER TABLE users ADD COLUMN pfind smallint NOT NULL DEFAULT 1;

UPDATE users
  SET registered = 1191004915
  WHERE registered = 0;
UPDATE votes
  SET date = 1191004915
  WHERE date = 0;

ALTER TABLE vnr RENAME COLUMN relation TO rel_old;
ALTER TABLE vnr ADD COLUMN relation varchar(32) NOT NULL DEFAULT 'Original release';

