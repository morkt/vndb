
-- Create table for session data storage

CREATE TABLE sessions (
    uid integer NOT NULL REFERENCES users(id);
    token character(40) NOT NULL,
    expiration timestamp without time zone DEFAULT (NOW() + '1 year'::interval) NOT NULL,
    PRIMARY KEY (uid, token)
);

-- Add column to users for salt storage

ALTER TABLE users ADD COLUMN salt character(9) NOT NULL DEFAULT ''::bpchar;

