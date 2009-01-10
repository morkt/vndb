
-- custom CSS
ALTER TABLE users ADD COLUMN customcss text NOT NULL DEFAULT '';



-- patch flag
ALTER TABLE releases_rev ADD COLUMN patch BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE releases_rev SET patch = TRUE
  WHERE EXISTS(SELECT 1 FROM releases_media rm WHERE rm.rid = id AND rm.medium = 'pa ');
DELETE FROM releases_media WHERE medium = 'pa ';

