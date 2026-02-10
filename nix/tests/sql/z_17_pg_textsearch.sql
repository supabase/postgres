-- Test pg_textsearch extension (BM25 ranked text search)
create schema ts;

create table ts.docs (
    id serial primary key,
    content text
);

insert into ts.docs (content) values
    ('PostgreSQL is a powerful relational database system'),
    ('BM25 is a ranking function used in search engines');

create index docs_bm25_idx on ts.docs using bm25(content) with (text_config='english');

-- Verify BM25 index was created
select indexname, indexdef from pg_indexes
where schemaname = 'ts' and indexname = 'docs_bm25_idx';

-- Verify BM25 search returns results (check count, not exact scores)
select count(*) from ts.docs where content <@> 'database' < 1.0;

drop schema ts cascade;
