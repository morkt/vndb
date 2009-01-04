
-- custom CSS
ALTER TABLE users ADD COLUMN customcss text NOT NULL DEFAULT '';

-- patch flag
ALTER TABLE releases_rev ADD COLUMN patch BOOLEAN NOT NULL DEFAULT FALSE;

