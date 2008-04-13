-- update c_* columns in vn
SELECT update_vncache(0), calculate_rating();

-- update changes.prev columns
SELECT update_prev('vn', ''), update_prev('releases', ''), update_prev('producers', '');

-- check...
 SELECT 'r', id FROM releases_rev rr
  WHERE NOT EXISTS(SELECT 1 FROM releases_vn rv WHERE rr.id = rv.rid)
UNION
 SELECT c.type::varchar, id FROM changes c
  WHERE (c.type = 0 AND NOT EXISTS(SELECT 1 FROM vn_rev vr WHERE vr.id = c.id))
     OR (c.type = 1 AND NOT EXISTS(SELECT 1 FROM releases_rev rr WHERE rr.id = c.id))
     OR (c.type = 2 AND NOT EXISTS(SELECT 1 FROM producers_rev pr WHERE pr.id = c.id));

