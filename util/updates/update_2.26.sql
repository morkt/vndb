-- No more 'staffedit' permission flag
UPDATE users SET perm = (perm & ~8);

-- Removed support for sha256-hashed passwords
UPDATE users SET passwd = '' WHERE length(passwd) = 41;

-- Need to regenerate all relation graphs in the switch to HTML5
UPDATE vn SET rgraph = NULL;
UPDATE producers SET rgraph = NULL;
