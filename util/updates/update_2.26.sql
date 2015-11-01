-- No more 'staffedit' permission flag
UPDATE users SET perm = (perm & ~8);

-- Removed support for sha256-hashed passwords
UPDATE users SET passwd = '' WHERE length(passwd) = 41;
