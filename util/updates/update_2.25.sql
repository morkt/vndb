ALTER TYPE credit_type ADD VALUE 'scenario' BEFORE 'script';


BEGIN;
-- There are no entries in the database where a single aid has both a script
-- and a staff role, and where a note has been associated with the script role.
-- So this conversion does not attempt to merge notes when merging roles.
UPDATE vn_staff vs SET role = 'staff', note = CASE WHEN note = '' THEN 'Scripting' ELSE note END
  WHERE role = 'script' AND NOT EXISTS(SELECT 1 FROM vn_staff v2 where v2.vid = vs.vid AND v2.aid = vs.aid AND role = 'staff');
UPDATE vn_staff vs SET note = CASE WHEN note = '' THEN 'Scripting' ELSE note || ', Scripting' END
  WHERE role = 'staff' AND EXISTS(SELECT 1 FROM vn_staff v2 where v2.vid = vs.vid AND v2.aid = vs.aid AND role = 'script');
DELETE FROM vn_staff WHERE role = 'script';
COMMIT;


-- Some new (or, well, old) platforms
ALTER TYPE platform ADD VALUE 'fmt' BEFORE 'gba';
ALTER TYPE platform ADD VALUE 'pce' BEFORE 'pcf';
ALTER TYPE platform ADD VALUE 'x68' BEFORE 'xb1';

