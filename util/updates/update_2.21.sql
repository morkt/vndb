
-- New resolution added on index 5
UPDATE releases_rev SET resolution = resolution + 1 WHERE resolution >= 5;


-- Old MD5 passwords can't be used anymore, so delete them
UPDATE users SET passwd = '' WHERE salt = '';

