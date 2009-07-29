
-- Create table for session data storage

CREATE TABLE sessions (
    uid integer NOT NULL REFERENCES users(id) DEFERRABLE INITIALLY DEFERRED;
    token character(40) NOT NULL,
    expiration bigint DEFAULT 0 NOT NULL,
    PRIMARY KEY (uid, token)
);

-- Add column to users for salt storage

ALTER TABLE users ADD COLUMN salt character(9) NOT NULL DEFAULT '';

