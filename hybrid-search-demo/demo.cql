-- Hybrid search demo. Run after schema.cql and data.cql, once ./wait-for-indexes.sh reports all
-- four indexes SERVING. Paste the queries one at a time into cqlsh, or run the whole file with
--   podman-compose exec scylla cqlsh -f /demo/demo.cql
--
-- EXPAND ON prints one row per block, one column per line, so that the wide excerpt columns stay
-- readable; EXPAND OFF returns to the table view for the queries without an excerpt.
--
-- Vocabulary:
--   BM25(col, 'term')  / ANN(col, [vector])   the search itself; in ORDER BY it asks for the search,
--                                            in SELECT it reports what the search said: (score, rank)
--   BM25_SCORE / ANN_SCORE                    the score half on its own
--   BM25_RANK  / ANN_RANK                     the rank half on its own, 1 = best, counted in the index's answer
--   BM25_HIGHLIGHT(col, 'term')               an excerpt of the row's text with the matched terms in <b></b>
--   RRF(search, search, ...)                  reciprocal-rank fusion: sum(1 / (60 + rank)) over the searches
--                                            that found the row; rows found by several searches rise.
--
-- A search that did not find a row reports the pair (null, null), which cqlsh prints as
-- (None, None). cqlsh also prints a harmless "Failed to format value (None, None)" line after such a
-- result: a cqlsh formatting bug with nulls inside a tuple, not an error from the server.

-- ---------------------------------------------------------------------------------------------
-- 0. The data
--    Eight articles, three topics. Vectors are [databases, animals, cooking].
-- ---------------------------------------------------------------------------------------------
-- Everything, one row per block...
EXPAND ON;
SELECT * FROM demo.articles;

-- ...and the table without the long body column.
EXPAND OFF;
SELECT id, title, title_vec, body_vec FROM demo.articles;

-- ---------------------------------------------------------------------------------------------
-- 1. One vector search: score and rank
--    Query vector = "animals".
-- ---------------------------------------------------------------------------------------------
EXPAND OFF;
SELECT id, title,
       ANN(body_vec, [0.1, 0.8, 0.1])       AS hit,
       ANN_SCORE(body_vec, [0.1, 0.8, 0.1]) AS similarity,
       ANN_RANK(body_vec, [0.1, 0.8, 0.1])  AS rank
  FROM demo.articles
 ORDER BY ANN(body_vec, [0.1, 0.8, 0.1])
 LIMIT 4;

-- ---------------------------------------------------------------------------------------------
-- 2. One full-text search: score, rank, excerpt
--    The score, the rank and an excerpt for every hit. A single BM25 search needs both the WHERE
--    and the ORDER BY clause.
-- ---------------------------------------------------------------------------------------------
-- The pair and its two halves...
EXPAND OFF;
SELECT id, title,
       BM25(body, 'fast')           AS hit,
       BM25_SCORE(body, 'fast')     AS score,
       BM25_RANK(body, 'fast')      AS rank
  FROM demo.articles
 WHERE BM25(body, 'fast') > 0
 ORDER BY BM25(body, 'fast')
 LIMIT 5;

-- ...and the pair with an excerpt, one row per block.
EXPAND ON;
SELECT id, title,
       BM25(body, 'fast')           AS hit,
       BM25_HIGHLIGHT(body, 'fast') AS excerpt
  FROM demo.articles
 WHERE BM25(body, 'fast') > 0
 ORDER BY BM25(body, 'fast')
 LIMIT 5;

-- ---------------------------------------------------------------------------------------------
-- 3. Hybrid: vector search + full-text search
--    A vector search ("animals") and a full-text search ('fast') fused. Rows found by both
--    searches (the fast animals) come first; rows found by only one follow, with null in the other
--    search's column and no excerpt for a row the text search did not match.
-- ---------------------------------------------------------------------------------------------
-- Table view first, without the excerpt, so that the ranking is easy to read...
EXPAND OFF;
SELECT id, title,
       ANN(body_vec, [0.1, 0.8, 0.1]) AS ann_hit,
       BM25(body, 'fast')             AS bm25_hit
  FROM demo.articles
 ORDER BY RRF(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'))
 LIMIT 6;

-- ...then the same search with the excerpt, one row per block.
EXPAND ON;
SELECT id, title,
       ANN(body_vec, [0.1, 0.8, 0.1]) AS ann_hit,
       BM25(body, 'fast')             AS bm25_hit,
       BM25_HIGHLIGHT(body, 'fast')   AS excerpt
  FROM demo.articles
 ORDER BY RRF(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'))
 LIMIT 6;

-- ---------------------------------------------------------------------------------------------
-- 4. Two vector searches fused
--    Titles near "databases", bodies near "cooking".
-- ---------------------------------------------------------------------------------------------
EXPAND OFF;
SELECT id, title,
       ANN(title_vec, [1, 0, 0]) AS title_hit,
       ANN(body_vec, [0, 0, 1])  AS body_hit
  FROM demo.articles
 ORDER BY RRF(ANN(title_vec, [1, 0, 0]), ANN(body_vec, [0, 0, 1]))
 LIMIT 5;

-- ---------------------------------------------------------------------------------------------
-- 5. Two full-text searches fused
--    'database' in the title, 'index' in the body. Each search is one request to its own index;
--    a row either search found comes back, with null where the other search did not find it.
--    No WHERE clause: RRF decides what is a hit.
-- ---------------------------------------------------------------------------------------------
-- Table view first, without the excerpt, so that the ranking is easy to read...
EXPAND OFF;
SELECT id, title,
       BM25(title, 'database')  AS title_hit,
       BM25(body, 'index')      AS body_hit
  FROM demo.articles
 ORDER BY RRF(BM25(title, 'database'), BM25(body, 'index'))
 LIMIT 5;

-- ...then the same search with an excerpt from each text search, one row per block. The title
-- excerpt is the whole title, highlighted, so it takes the place of the title column.
EXPAND ON;
SELECT id,
       BM25_HIGHLIGHT(title, 'database') AS title_excerpt,
       BM25(title, 'database')           AS title_hit,
       BM25_HIGHLIGHT(body, 'index')     AS body_excerpt,
       BM25(body, 'index')               AS body_hit
  FROM demo.articles
 ORDER BY RRF(BM25(title, 'database'), BM25(body, 'index'))
 LIMIT 5;

-- ---------------------------------------------------------------------------------------------
-- 6. Three searches
--    Bodies near "cooking", plus 'lazy dog' in the title and in the body.
-- ---------------------------------------------------------------------------------------------
EXPAND OFF;
SELECT id, title,
       ANN(body_vec, [0, 0, 1])  AS cooking_hit,
       BM25(title, 'lazy dog')   AS title_hit,
       BM25(body, 'lazy dog')    AS body_hit
  FROM demo.articles
 ORDER BY RRF(ANN(body_vec, [0, 0, 1]), BM25(title, 'lazy dog'), BM25(body, 'lazy dog'))
 LIMIT 5;

-- ---------------------------------------------------------------------------------------------
-- 7. Your own fusion function
--    The ordering may be any function call that names at least one search and answers with a
--    float, so a UDF taking the (score, rank) pairs works, with extra arguments: constants, or
--    even a column of the row. (UDFs are enabled in docker-compose.yml with
--    --experimental-features udf --enable-user-defined-functions 1.)
-- ---------------------------------------------------------------------------------------------
EXPAND OFF;
-- Weighted score fusion: 80% vector similarity, 20% BM25 score, the fused value selected too.
CREATE OR REPLACE FUNCTION demo.blend(a frozen<tuple<float, int>>, b frozen<tuple<float, int>>, w float)
  CALLED ON NULL INPUT RETURNS float LANGUAGE lua AS $$
    local sa = (a and a[1]) or 0
    local sb = (b and b[1]) or 0
    return w * sa + (1 - w) * sb
  $$;

SELECT id, title,
       ANN(body_vec, [0.1, 0.8, 0.1]) AS ann_hit,
       BM25(body, 'fast')             AS bm25_hit,
       demo.blend(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'), 0.8) AS blended
  FROM demo.articles
 ORDER BY demo.blend(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'), 0.8)
 LIMIT 6;

-- A column of the row as an extra argument: here the id acts as a boost.
CREATE OR REPLACE FUNCTION demo.blend_boost(a frozen<tuple<float, int>>, b frozen<tuple<float, int>>, w float, boost int)
  CALLED ON NULL INPUT RETURNS float LANGUAGE lua AS $$
    local sa = (a and a[1]) or 0
    local sb = (b and b[1]) or 0
    return w * sa + (1 - w) * sb + (boost or 0)
  $$;

SELECT id, title,
       demo.blend_boost(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'), 0.8, id) AS boosted
  FROM demo.articles
 ORDER BY demo.blend_boost(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'), 0.8, id)
 LIMIT 6;

-- ---------------------------------------------------------------------------------------------
-- 8. Guard rails
--    What is refused, and why.
-- ---------------------------------------------------------------------------------------------
EXPAND OFF;
-- A search is identified by its kind and its column, so two BM25 terms, or two ANN vectors, on one
-- column are refused.
SELECT id, title FROM demo.articles
 ORDER BY RRF(BM25(body, 'fast'), BM25(body, 'dog'))
 LIMIT 5;

SELECT id, title FROM demo.articles
 ORDER BY RRF(ANN(body_vec, [0, 0, 1]), ANN(body_vec, [0, 1, 0]))
 LIMIT 5;

-- For BM25 the one search can say it instead: the term is a query of its own, so 'fast OR dog'
-- (the same as 'fast dog') finds either word and ranks the rows with both first...
EXPAND ON;
SELECT id, title,
       BM25(body, 'fast OR dog')           AS hit,
       BM25_HIGHLIGHT(body, 'fast OR dog') AS excerpt
  FROM demo.articles
 WHERE BM25(body, 'fast OR dog') > 0
 ORDER BY BM25(body, 'fast OR dog')
 LIMIT 5;

-- ...and 'fast AND dog' only the rows with both. A query vector has no such operators, so for ANN
-- there is no way to put two vectors of one column into one query.
EXPAND OFF;
SELECT id, title, BM25(body, 'fast AND dog') AS hit
  FROM demo.articles
 WHERE BM25(body, 'fast AND dog') > 0
 ORDER BY BM25(body, 'fast AND dog')
 LIMIT 5;

-- A fused query takes no WHERE clause: which restrictions a search can apply is a property of
-- the index doing the work, and here there are two.
SELECT id FROM demo.articles
 WHERE BM25(body, 'fast') > 0
 ORDER BY RRF(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'))
 LIMIT 5;

-- An ordering must name at least one search...
SELECT id FROM demo.articles ORDER BY RRF(1, 2) LIMIT 5;

-- ...and so must one by your own function from section 7.
SELECT id FROM demo.articles ORDER BY demo.blend((1.0, 1), (2.0, 2), 0.5) LIMIT 3;

-- A SELECT may only report a search the ORDER BY runs.
SELECT id, BM25_SCORE(title, 'fast') AS s FROM demo.articles
 ORDER BY ANN(body_vec, [0.1, 0.8, 0.1])
 LIMIT 5;
