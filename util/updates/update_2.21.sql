
-- New resolution added on index 5
UPDATE releases_rev SET resolution = resolution + 1 WHERE resolution >= 5;


-- Old MD5 passwords can't be used anymore, so delete them
UPDATE users SET passwd = '' WHERE salt = '';


-- Email addresses now have to be confirmed upon registration
-- This boolean column won't really checked on login, it's just here for
-- administration purposes. The passwd/salt columns contain a
-- password-reset-token, so the user won't be able to login directly after
-- registration anyway.
ALTER TABLE users ADD COLUMN email_confirmed boolean NOT NULL DEFAULT FALSE;
UPDATE users SET email_confirmed = TRUE;

