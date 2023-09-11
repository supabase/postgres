CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;
SELECT plan(4);

SELECT results_eq(
    'SELECT count(*)::int FROM public.countries',
    ARRAY[ 249 ]
);

SELECT results_eq(
    'SELECT count(*)::int FROM public.countries where continent = ''Europe''',
    ARRAY[ 45 ]
);

SELECT results_eq(
    'SELECT count(*)::int FROM public.european_countries',
    ARRAY[ 45 ]
);

SELECT results_eq(
    'SELECT count(*) FROM public.countries where continent = ''Europe''',
    'SELECT count(*) FROM public.european_countries'
);

SELECT * FROM finish();
ROLLBACK;
