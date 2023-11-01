BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
create extension if not exists h3-pg with schema "extensions";
SELECT plan(1);
SELECT is(
    h3_lat_lng_to_cell(POINT('37.3615593,-122.0553238')::geometry, 5),
    '85e35e73fffffff',
    'Test for h3_lat_lng_to_cell function with a specified latitude, longitude, and resolution'
);
SELECT * FROM finish();
ROLLBACK;
