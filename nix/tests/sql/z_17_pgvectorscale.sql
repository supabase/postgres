CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;

CREATE SCHEMA diskann_test;

CREATE TABLE diskann_test.documents (
    id SERIAL PRIMARY KEY,
    embedding VECTOR(3),
    labels SMALLINT[],
    content TEXT
);

INSERT INTO diskann_test.documents (embedding, labels, content) VALUES
    ('[1,2,3]', ARRAY[1,2], 'First document'),
    ('[2,3,4]', ARRAY[2,3], 'Second document'),
    ('[3,4,5]', ARRAY[1,3], 'Third document'),
    ('[4,5,6]', ARRAY[1], 'Fourth document'),
    ('[5,6,7]', ARRAY[2], 'Fifth document'),
    ('[6,7,8]', NULL, 'Sixth document'),
    (NULL, ARRAY[1,2], 'Seventh document');

CREATE INDEX diskann_cosine_idx ON diskann_test.documents USING diskann (embedding vector_cosine_ops);
CREATE INDEX diskann_l2_idx ON diskann_test.documents USING diskann (embedding vector_l2_ops);
CREATE INDEX diskann_ip_idx ON diskann_test.documents USING diskann (embedding vector_ip_ops);

CREATE INDEX diskann_label_idx ON diskann_test.documents USING diskann (embedding vector_cosine_ops, labels);

SELECT id, embedding, content 
FROM diskann_test.documents
WHERE embedding IS NOT NULL
ORDER BY embedding <=> '[2,2,3]'
LIMIT 3;

SELECT id, embedding, labels, content
FROM diskann_test.documents  
WHERE labels && ARRAY[1]
ORDER BY embedding <=> '[2,2,3]'
LIMIT 3;

SELECT id, embedding, labels, content
FROM diskann_test.documents
WHERE labels && ARRAY[2,3]
ORDER BY embedding <-> '[3,3,4]'
LIMIT 3;

SELECT id, embedding, labels, content
FROM diskann_test.documents
WHERE content LIKE '%Third%'
ORDER BY embedding <#> '[3,3,4]'
LIMIT 2;

CREATE INDEX diskann_custom_idx ON diskann_test.documents 
USING diskann (embedding vector_cosine_ops) 
WITH (num_neighbors=30, search_list_size=80);

SELECT id, embedding, content
FROM diskann_test.documents
WHERE embedding IS NOT NULL
ORDER BY embedding <=> '[1,1,2]'
LIMIT 2;

SET diskann.query_rescore = 20;
SET diskann.query_search_list_size = 50;

SELECT id, embedding, content
FROM diskann_test.documents
WHERE embedding IS NOT NULL
ORDER BY embedding <=> '[4,4,5]'
LIMIT 2;

RESET diskann.query_rescore;
RESET diskann.query_search_list_size;

WITH ranked_results AS MATERIALIZED (
    SELECT id, embedding, embedding <=> '[3,3,3]' AS distance
    FROM diskann_test.documents
    WHERE embedding IS NOT NULL
    ORDER BY distance
    LIMIT 3
)
SELECT id, distance FROM ranked_results ORDER BY distance;

DROP SCHEMA diskann_test CASCADE;