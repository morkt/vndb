
-- custom CSS
ALTER TABLE users ADD COLUMN customcss text NOT NULL DEFAULT '';



-- patch flag
ALTER TABLE releases_rev ADD COLUMN patch BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE releases_rev SET patch = TRUE
  WHERE EXISTS(SELECT 1 FROM releases_media rm WHERE rm.rid = id AND rm.medium = 'pa ');
DELETE FROM releases_media WHERE medium = 'pa ';



-- popularity calculation
ALTER TABLE vn ADD COLUMN c_popularity real NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION update_vnpopularity() RETURNS void AS $$
BEGIN
  CREATE OR REPLACE TEMP VIEW tmp_pop1 (uid, vid, rank) AS
    SELECT v.uid, v.vid, sqrt(count(*))::real FROM votes v JOIN votes v2 ON v.uid = v2.uid AND v2.vote < v.vote GROUP BY v.vid, v.uid;
  CREATE OR REPLACE TEMP VIEW tmp_pop2 (vid, win) AS
    SELECT vid, sum(rank) FROM tmp_pop1 GROUP BY vid;
  UPDATE vn SET c_popularity = COALESCE((SELECT win/(SELECT MAX(win) FROM tmp_pop2) FROM tmp_pop2 WHERE vid = id), 0);
  RETURN;
END;
$$ LANGUAGE plpgsql;

SELECT update_vnpopularity();



-- store the IP address used to register
ALTER TABLE users ADD COLUMN ip inet NOT NULL DEFAULT '0.0.0.0';


