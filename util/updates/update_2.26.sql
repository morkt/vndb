-- No more 'staffedit' permission flag
UPDATE users SET perm = (perm & ~8);
