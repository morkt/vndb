ALTER TABLE vn ADD COLUMN length smallint NOT NULL DEFAULT 0;

DELETE FROM vn_categories WHERE SUBSTR(category, 1, 1) = 'a';
ALTER TABLE vnr ADD COLUMN minage smallint NOT NULL DEFAULT -1;

ALTER TABLE vn ADD COLUMN l_wp varchar(150) NOT NULL DEFAULT '';
ALTER TABLE vn ADD COLUMN l_cisv integer NOT NULL DEFAULT 0;


UPDATE vn SET
  c_released = COALESCE((
      SELECT SUBSTRING(COALESCE(MIN(released), '0000-00') from 1 for 7)
      FROM vnr r1
      WHERE r1.vid = vn.id
      AND r1.r_rel = 0
      AND r1.relation NOT ILIKE 'trial'
      GROUP BY r1.vid
    ), '0000-00'),
  c_languages = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT language
      FROM vnr r2
      WHERE r2.vid = vn.id
      AND r2.r_rel = 0
      AND r2.relation NOT ILIKE 'trial'
      GROUP BY language
      ORDER BY language
    ), '/'), '');
