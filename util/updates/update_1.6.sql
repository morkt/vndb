ALTER TABLE vnr DROP COLUMN rel_old;
ALTER TABLE vnr ALTER COLUMN released DROP NOT NULL;
ALTER TABLE vnr ALTER COLUMN released SET DEFAULT NULL;
UPDATE vnr SET released = NULL WHERE released = '0000-00-00';

ALTER TABLE vn RENAME COLUMN c_years TO c_released;
UPDATE vn SET c_released = '0000-00';
ALTER TABLE vn ALTER COLUMN c_released SET DEFAULT '0000-00';
ALTER TABLE vn ALTER COLUMN c_released TYPE character(7);
UPDATE vn SET
  c_released = COALESCE((SELECT
      SUBSTRING(COALESCE(MIN(released), '0000-00') from 1 for 7)
      FROM vnr r1
      WHERE r1.vid = vn.id
      AND r1.r_rel = 0
      GROUP BY r1.vid
    ), '0000-00');


ALTER TABLE vn_relations DROP COLUMN lastmod;
ALTER TABLE vn ADD COLUMN rgraph bytea NOT NULL DEFAULT '';
