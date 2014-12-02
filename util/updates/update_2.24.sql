-- Session tokens are stored in the database as a SHA-1 on the actual token
-- now.  Note that this query should be executed only once, otherwise any
-- existing sessions will be invalidated.
-- CREATE EXTENSION pgcrypto;
UPDATE sessions SET token = digest(token, 'sha1');
-- DROP EXTENSION pgcrypto;


-- No more 'charedit' permission flag
UPDATE users SET perm = (perm & ~8);


-- Completely remove l_vnn column
ALTER TABLE vn_rev DROP COLUMN l_vnn;
