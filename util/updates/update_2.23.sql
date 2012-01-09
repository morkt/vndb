-- Two extra indices for performance

CREATE INDEX releases_producers_rid ON releases_producers (rid);
CREATE INDEX tags_vn_vid ON tags_vn (vid);



-- Extra language for ukrainian

ALTER TYPE language RENAME TO language_old;
CREATE TYPE language AS ENUM ('cs', 'da', 'de', 'en', 'es', 'fi', 'fr', 'hu', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt-pt', 'pt-br', 'ru', 'sk', 'sv', 'tr', 'uk', 'vi', 'zh'); 
ALTER TABLE producers_rev ALTER COLUMN lang DROP DEFAULT;
ALTER TABLE producers_rev ALTER COLUMN lang TYPE language USING lang::text::language;
ALTER TABLE producers_rev ALTER COLUMN lang SET DEFAULT 'ja';

ALTER TABLE releases_lang ALTER COLUMN lang TYPE language USING lang::text::language;

ALTER TABLE vn ALTER COLUMN c_languages DROP DEFAULT;
DROP TRIGGER vn_relgraph_notify ON vn;
ALTER TABLE vn ALTER COLUMN c_languages TYPE language[] USING c_languages::text[]::language[];
CREATE TRIGGER vn_relgraph_notify AFTER UPDATE ON vn FOR EACH ROW
  WHEN (OLD.rgraph      IS DISTINCT FROM NEW.rgraph
     OR OLD.latest      IS DISTINCT FROM NEW.latest
     OR OLD.c_released  IS DISTINCT FROM NEW.c_released
     OR OLD.c_languages IS DISTINCT FROM NEW.c_languages
  ) EXECUTE PROCEDURE vn_relgraph_notify();
ALTER TABLE vn ALTER COLUMN c_languages SET DEFAULT '{}';

ALTER TABLE vn ALTER COLUMN c_olang DROP DEFAULT;
ALTER TABLE vn ALTER COLUMN c_olang TYPE language[] USING c_olang::text[]::language[];
ALTER TABLE vn ALTER COLUMN c_olang SET DEFAULT '{}';

DROP TYPE language_old;
