-- migrate:up
-- TODO: remove this migration once STORAGE-211 is completed
-- DRI: bobbie
grant all on storage.buckets, storage.objects to postgres with grant option;

-- migrate:down
