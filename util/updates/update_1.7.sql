ALTER TABLE producers ADD COLUMN "desc" text NOT NULL DEFAULT '';


--ALTER TABLE users ADD COLUMN flags bit(4) NOT NULL DEFAULT B'1110';
--UPDATE users SET flags = pvotes::bit || pfind::bit || plist::bit || pign_nsfw::bit;
ALTER TABLE users ADD COLUMN flags integer NOT NULL DEFAULT 7;
UPDATE users SET flags = pvotes + pfind*2 + plist*4 + pign_nsfw*8;

--ALTER TABLE users DROP COLUMN pvotes;
--ALTER TABLE users DROP COLUMN pfind;
--ALTER TABLE users DROP COLUMN plist;
--ALTER TABLE users DROP COLUMN pign_nsfw;


--ALTER TABLE vn ADD COLUMN categories integer NOT NULL DEFAULT 0;
--UPDATE vn SET categories =
--  COALESCE((SELECT  1 FROM vn_categories WHERE vid = vn.id AND category = 'a18'), 0)
-- +COALESCE((SELECT  2 FROM vn_categories WHERE vid = vn.id AND category = 'aaa'), 0)
-- +COALESCE((SELECT  4 FROM vn_categories WHERE vid = vn.id AND category = 'ajo'), 0)
-- +COALESCE((SELECT  8 FROM vn_categories WHERE vid = vn.id AND category = 'ako'), 0)
-- +COALESCE((SELECT 16 FROM vn_categories WHERE vid = vn.id AND category = 'ase'), 0)
-- +COALESCE((SELECT 32 FROM vn_categories WHERE vid = vn.id AND category = 'asj'), 0)
-- +COALESCE((SELECT 64 FROM vn_categories WHERE vid = vn.id AND category = 'asn'), 0);
