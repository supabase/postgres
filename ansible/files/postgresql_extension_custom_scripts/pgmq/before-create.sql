-- clear a leftover drop_queue(text, boolean) compat shim from a prior
-- install: it isn't an extension member, so DROP EXTENSION never removes it,
-- and pgmq's own install script would otherwise collide with it
drop function if exists pgmq.drop_queue(text, boolean);
