# Hybrid search demo: ANN + BM25 + highlighting in one CQL query

A small, self-contained demo of ScyllaDB's hybrid search
([scylladb/scylladb#31580](https://github.com/scylladb/scylladb/pull/31580), merged to master): one `SELECT` served by several
external searches at once, vector (ANN) and full-text (BM25), fused with reciprocal-rank fusion,
reporting every search's own score and rank and highlighting the matched text.

Eight articles, three topics, hand-made 3-dimensional "embeddings". Everything runs in two local
containers.

## What you need

- `podman` (rootless is fine), `buildah`, and `podman-compose`. (`docker-compose` works too once the podman socket is up: `systemctl --user start podman.socket`.)

Both images are published, so nothing is built:

- ScyllaDB `docker.io/scylladb/scylla-nightly:2026.4.0-dev-0.20261013.09445539ad64`, the nightly
  build of master at `09445539ad`, which has the hybrid search merge. No release has it yet.
- Vector Store `docker.io/scylladb/vector-store:1.12.0`, the latest release (the `/highlight`
  endpoint the demo needs is there since 1.11.0).

The `scylladb` and `vector-store` submodules are pinned on the commits of these images, for
reading the code. To run the demo on other checkouts, build images from them with
`./build-images.sh [scylla-src] [vector-store-src]` and point the compose file at them:

```sh
SCYLLA_IMAGE=localhost/scylla-hybrid:dev VECTOR_STORE_IMAGE=localhost/vector-store-hybrid:dev podman-compose up -d
```

## Set-up

```sh
podman-compose up -d                                # scylla first, vector store when scylla is healthy
podman-compose exec scylla cqlsh -f /demo/schema.cql
podman-compose exec scylla cqlsh -f /demo/data.cql
./wait-for-indexes.sh                               # the Vector Store full-scans the table once per index
podman-compose exec scylla cqlsh                    # then paste queries from demo.cql
```

`podman-compose exec scylla cqlsh -f /demo/demo.cql` runs the whole script in one go, including the
deliberately failing statements of section 8, which cqlsh reports and moves past.
`podman exec hybrid-demo-scylla cqlsh ...` works just as well as `podman-compose exec scylla cqlsh ...`.

Tear down with `podman-compose down -v`.

## The schema

`demo.articles` has two text columns and two vector columns, one index on each
(see [schema.cql](schema.cql)):

| column | type | index |
|---|---|---|
| `title` | text | `articles_title_fts`, `fulltext_index` |
| `body` | text | `articles_body_fts`, `fulltext_index` |
| `title_vec` | vector<float, 3> | `articles_title_ann`, `vector_index`, cosine |
| `body_vec` | vector<float, 3> | `articles_body_ann`, `vector_index`, cosine |

The vectors are three topic axes, `[databases, animals, cooking]`, so a query vector like
`[0.1, 0.8, 0.1]` means "about animals". The rows are chosen so text and vectors disagree: the word
`fast` appears in database, animal and cooking rows, and `lazy dog` in an animal row and a cooking
row ([data.cql](data.cql)).

The vector indexes keep the default `f32` quantization. That leaves rescoring off, so the rank a
query reports is the Vector Store's own; a rescored index reports rank `0` for now.

## The functions

| in `ORDER BY` | in `SELECT` | meaning |
|---|---|---|
| `BM25(col, 'term')` | `BM25(col, 'term')` | the full-text search; selected, it reports `(score, rank)` |
| `ANN(col, [v])` | `ANN(col, [v])` | the vector search; selected, it reports `(similarity, rank)` |
| | `BM25_SCORE`, `ANN_SCORE` | the score half on its own |
| | `BM25_RANK`, `ANN_RANK` | the rank half: the row's position in that index's answer, 1 = best |
| | `BM25_HIGHLIGHT(col, 'term')` | an excerpt of the row's text, matched terms wrapped in `<b></b>`; `null` if the search did not match the row |
| `RRF(search, search, ...)` | | reciprocal-rank fusion, `sum(1 / (60 + rank))` over the searches that found the row |

Rules worth knowing when writing your own queries:

- A search is identified by its kind and its column. Two `BM25()` calls on different columns are
  two searches and two requests; every call on the same column shares one request, however many
  of `BM25`, `BM25_SCORE`, `BM25_RANK`, `BM25_HIGHLIGHT` the query writes.
- `SELECT` may only report a search that `ORDER BY` runs, with the same column and the same
  term or vector.
- A single `BM25` search still needs `WHERE BM25(col, 'term') > 0`; a single `ANN` search needs
  no `WHERE`; a fused `RRF(...)` ordering accepts no `WHERE` at all.
- `LIMIT` is mandatory (at most 1000) and is applied after fusion. Each search is asked for
  `LIMIT` rows, a vector index with the `oversampling` option for that many times more, so a row
  one search ranked below the limit reports `(null, null)` for it even when another search found
  it.
- Scores are not fused, ranks are: a BM25 score of 3.5 and a cosine similarity of 0.9 are not on
  one scale, but "first in this search" and "second in that one" are.

## The demo, query by query

Outputs below are from a real run; see [demo.cql](demo.cql) for the exact statements.

The fused examples report each search as its `(score, rank)` pair; only the two single-search
sections project the halves, to introduce them. A search that did not find a row reports
`(null, null)`, which cqlsh prints as `(None, None)`. cqlsh also prints a harmless
`Failed to format value (None, None)` line after such a result: a cqlsh formatting bug with nulls
inside a tuple, not a server error; section 0 gets a similar
`Unexpected number of subtypes 3 - [float, 3]` line for the vector columns. The excerpt queries are
run with `EXPAND ON` in [demo.cql](demo.cql); the tables below are the `EXPAND OFF` view.

### 1. One vector search: the pair and its halves

```sql
SELECT id, title, ANN(body_vec, [0.1, 0.8, 0.1]) AS hit,
       ANN_SCORE(body_vec, [0.1, 0.8, 0.1]) AS similarity, ANN_RANK(body_vec, [0.1, 0.8, 0.1]) AS rank
  FROM demo.articles ORDER BY ANN(body_vec, [0.1, 0.8, 0.1]) LIMIT 4;
```
```
 id | title                                   | hit           | similarity | rank
----+-----------------------------------------+---------------+------------+------
  3 |                     The quick brown fox | (0.996151, 1) |   0.996151 |    1
  4 |                        Wombats dig fast | (0.992366, 2) |   0.992366 |    2
  8 |                  Cooking for a lazy dog | (0.862486, 3) |   0.862486 |    3
  1 | ScyllaDB is a fast distributed database | (0.615542, 4) |   0.615542 |    4
```

`ANN()` selected reports what the search said about the row as a `(similarity, rank)` pair;
`ANN_SCORE()` and `ANN_RANK()` are its two halves. The "animals" query vector finds the two animal
rows, then the dog-food recipe. The similarity is the Vector Store's cosine similarity mapped to
`[0, 1]`, so an orthogonal vector scores `0.5`.

### 2. One full-text search: score, rank, excerpt

```sql
SELECT id, title, BM25_SCORE(body, 'fast') AS score, BM25_RANK(body, 'fast') AS rank
  FROM demo.articles WHERE BM25(body, 'fast') > 0 ORDER BY BM25(body, 'fast') LIMIT 5;
```
```
 id | title                                   | score    | rank
----+-----------------------------------------+----------+------
  5 |                    Fast weeknight pasta | 0.792736 |    1
  4 |                        Wombats dig fast |  0.74861 |    2
  3 |                     The quick brown fox | 0.728339 |    3
  1 | ScyllaDB is a fast distributed database | 0.573144 |    4
```

Unlike an ANN search, a single BM25 search also needs `WHERE BM25(col, 'term') > 0`. Four of the
eight bodies contain `fast`, so four rows; the shortest body ranks first. The same search reported
as the pair, with the excerpt:

```sql
SELECT id, title, BM25(body, 'fast') AS hit, BM25_HIGHLIGHT(body, 'fast') AS excerpt
  FROM demo.articles WHERE BM25(body, 'fast') > 0 ORDER BY BM25(body, 'fast') LIMIT 5;
```
```
@ Row 1
---------+----------------------------------------------------------------------------------------------------------------------------
 id      | 5
 title   | Fast weeknight pasta
 hit     | (0.792736, 1)
 excerpt | A <b>fast</b> pasta recipe: garlic, olive oil and chili with spaghetti. Dinner in fifteen minutes

@ Row 2
---------+----------------------------------------------------------------------------------------------------------------------------
 id      | 4
 title   | Wombats dig fast
 hit     | (0.74861, 2)
 excerpt | A wombat digs its burrow surprisingly <b>fast</b> for such a stocky animal. Wombats are nocturnal marsupials from Australia
(... rows 3 and 1 follow)
```

The excerpt is the Vector Store's Tantivy snippet of the row's own text, generated by a second
request issued after the rows were read; `BM25()`, `BM25_SCORE()`, `BM25_RANK()` all come out of
the first one.

### 3. Hybrid: vector search + full-text search

```sql
SELECT id, title, ANN(body_vec, [0.1, 0.8, 0.1]) AS ann_hit, BM25(body, 'fast') AS bm25_hit
  FROM demo.articles ORDER BY RRF(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast')) LIMIT 6;
```
```
 id | title                                   | ann_hit       | bm25_hit
----+-----------------------------------------+---------------+---------------
  3 |                     The quick brown fox | (0.996151, 1) | (0.728339, 3)
  4 |                        Wombats dig fast | (0.992366, 2) |  (0.74861, 2)
  5 |                    Fast weeknight pasta | (0.586057, 5) | (0.792736, 1)
  1 | ScyllaDB is a fast distributed database | (0.615542, 4) | (0.573144, 4)
  8 |                  Cooking for a lazy dog | (0.862486, 3) |  (None, None)
  7 |              Database indexes explained | (0.574635, 6) |  (None, None)
```

Two searches, two requests: one to the vector index, one to the full-text index. A row either
search found comes back, with `(None, None)` for the search that did not find it. There is no
`WHERE`: with several searches, RRF decides what counts as a hit. The fast animals (3 and 4) are
found high by both searches and lead. Rows 5 and 1 are text hits the vector search ranked low,
and still beat the vector-only rows 8 and 7. With `BM25_HIGHLIGHT(body, 'fast')` added (`EXPAND ON`
variant), the first four rows carry a `<b>fast</b>` excerpt and the last two `null`, from a third
request, `/highlight`, for the rows' text.

### 4. Two vector searches fused

```sql
SELECT id, title, ANN(title_vec, [1, 0, 0]) AS title_hit, ANN(body_vec, [0, 0, 1]) AS body_hit
  FROM demo.articles ORDER BY RRF(ANN(title_vec, [1, 0, 0]), ANN(body_vec, [0, 0, 1])) LIMIT 5;
```
```
 id | title                      | title_hit     | body_hit
----+----------------------------+---------------+---------------
  7 | Database indexes explained | (0.996942, 1) | (0.621268, 4)
  2 |  Vector search in ScyllaDB | (0.996139, 2) | (0.527735, 5)
  8 |     Cooking for a lazy dog | (0.577152, 4) | (0.884111, 3)
  6 |     Baking sourdough bread |  (None, None) |        (1, 1)
  5 |       Fast weeknight pasta |  (None, None) | (0.999376, 2)
```

"Database" titles against "cooking" bodies: nothing is good at both, so the rows both searches
return (7, 2 and 8) beat the rows only one of them returns, even rows 6 and 5, the first two of the
body search. That is what fusing ranks rather than scores does. Each search is asked for 5 rows,
so a row outside a search's top 5 reports `(None, None)` for it: the bread and pasta titles are a
long way from "databases".

### 5. Two full-text searches fused

```sql
SELECT id, title, BM25(title, 'database') AS title_hit, BM25(body, 'index') AS body_hit
  FROM demo.articles ORDER BY RRF(BM25(title, 'database'), BM25(body, 'index')) LIMIT 5;
```
```
 id | title                                   | title_hit    | body_hit
----+-----------------------------------------+--------------+--------------
  7 |              Database indexes explained | (1.30224, 1) | (2.73711, 1)
  1 | ScyllaDB is a fast distributed database | (1.14929, 2) | (None, None)
```

Two searches, two requests, one to each full-text index. Row 7 is found by both and wins; row 1 is
found only by the title search, so its body pair is `(None, None)` and, in the `EXPAND ON` variant
that adds `BM25_HIGHLIGHT(body, 'index')`, its excerpt is `null`.

### 6. Three searches, two excerpts

```sql
SELECT id, title, ANN(body_vec, [0, 0, 1]) AS cooking_hit,
       BM25(title, 'lazy dog') AS title_hit, BM25(body, 'lazy dog') AS body_hit
  FROM demo.articles
 ORDER BY RRF(ANN(body_vec, [0, 0, 1]), BM25(title, 'lazy dog'), BM25(body, 'lazy dog')) LIMIT 5;
```
```
 id | title                      | cooking_hit   | title_hit    | body_hit
----+----------------------------+---------------+--------------+--------------
  8 |     Cooking for a lazy dog | (0.884111, 3) | (3.64313, 1) |  (3.0995, 1)
  6 |     Baking sourdough bread |        (1, 1) | (None, None) | (None, None)
  5 |       Fast weeknight pasta | (0.999376, 2) | (None, None) | (None, None)
  3 |        The quick brown fox |  (None, None) | (None, None) | (2.69194, 2)
  7 | Database indexes explained | (0.621268, 4) | (None, None) | (None, None)
```

Row 8 is the only one all three searches agree on. The `EXPAND ON` variant adds an excerpt per
text search:

```
@ Row 4
---------------+-------------------------------------------------------------------------------------------------------------------------------------
 id            | 3
 title         | The quick brown fox
 cooking_hit   | (None, None)
 title_hit     | (None, None)
 title_excerpt | null
 body_hit      | (2.69194, 2)
 body_excerpt  | The quick brown fox jumps over the <b>lazy</b> <b>dog</b>. Foxes are fast and clever hunters that live at the edge of the forest
```

Each excerpt belongs to its own search: the title excerpt is `null` for row 3 because its title does
not match, while its body does.

### 7. Your own fusion function

The ordering may be any function call that names at least one search and answers with a `float`,
so a UDF over the `(score, rank)` pairs works, with extra arguments: constants, or a column of the
row. `docker-compose.yml` enables UDFs (`--experimental-features udf`,
`--enable-user-defined-functions 1`).

```sql
CREATE OR REPLACE FUNCTION demo.blend(a frozen<tuple<float, int>>, b frozen<tuple<float, int>>, w float)
  CALLED ON NULL INPUT RETURNS float LANGUAGE lua AS $$
    local sa = (a and a[1]) or 0
    local sb = (b and b[1]) or 0
    return w * sa + (1 - w) * sb
  $$;

SELECT id, title, ANN(body_vec, [0.1, 0.8, 0.1]) AS ann_hit, BM25(body, 'fast') AS bm25_hit,
       demo.blend(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'), 0.8) AS blended
  FROM demo.articles
 ORDER BY demo.blend(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast'), 0.8) LIMIT 6;
```
```
 id | title                                   | ann_hit       | bm25_hit      | blended
----+-----------------------------------------+---------------+---------------+----------
  4 |                        Wombats dig fast | (0.992366, 2) |  (0.74861, 2) | 0.943615
  3 |                     The quick brown fox | (0.996151, 1) | (0.728339, 3) | 0.942589
  8 |                  Cooking for a lazy dog | (0.862486, 3) |  (None, None) | 0.689989
  5 |                    Fast weeknight pasta | (0.586057, 5) | (0.792736, 1) | 0.627392
  1 | ScyllaDB is a fast distributed database | (0.615542, 4) | (0.573144, 4) | 0.607062
  7 |              Database indexes explained | (0.574635, 6) |  (None, None) | 0.459708
```

Weighting scores 80/20 rather than fusing ranks lifts the vector-only row 8 above the text hits
5 and 1, which RRF put ahead of it in section 3.
The same function selected in the `SELECT` list shows the value the rows were ranked by. A column
can be an argument too; `demo.blend_boost(..., 0.8, id)` in [demo.cql](demo.cql) adds the row's id
to the score and reorders the result by id.

### 8. Guard rails

The most interesting refusal is two searches of one column. A search is identified by its kind and
its column, so two terms, or two vectors, on one column are refused for either kind:

```
SELECT id, title FROM demo.articles ORDER BY RRF(BM25(body, 'fast'), BM25(body, 'dog')) LIMIT 5;
  -> InvalidRequest: BM25() in ORDER BY must use the same search term as the other BM25 calls on the same column

SELECT id, title FROM demo.articles ORDER BY RRF(ANN(body_vec, [0, 0, 1]), ANN(body_vec, [0, 1, 0])) LIMIT 5;
  -> InvalidRequest: ANN() in ORDER BY must use the same query vector as the other ANN calls on the same column
```

For BM25 one search can say it instead: the full-text index parses the term as a query, so
`'fast OR dog'` (the same as `'fast dog'`) finds either word, and the row with both comes first:

```sql
SELECT id, title, BM25(body, 'fast OR dog') AS hit, BM25_HIGHLIGHT(body, 'fast OR dog') AS excerpt
  FROM demo.articles WHERE BM25(body, 'fast OR dog') > 0 ORDER BY BM25(body, 'fast OR dog') LIMIT 5;
```
```
@ Row 1
---------+----------------------------------------------------------------------------------------------------------------------------
 id      | 3
 title   | The quick brown fox
 hit     | (2.07431, 1)
 excerpt | The quick brown fox jumps over the lazy <b>dog</b>. Foxes are <b>fast</b> and clever hunters that live at the edge of the forest

@ Row 2
---------+----------------------------------------------------------------------------------------------------------------------------
 id      | 8
 title   | Cooking for a lazy dog
 hit     | (1.78902, 2)
 excerpt | Homemade <b>dog</b> food: rice, chicken and carrots simmered together. Even a lazy <b>dog</b> gets excited about this dinner
(... rows 5, 4 and 1, the other 'fast' bodies, follow)
```

`'fast AND dog'` finds only row 3, `(2.07431, 1)`. A query vector has no such operators, so for ANN
there is no way to put two vectors of one column into one query.

The rest of the rules:

```
SELECT id FROM demo.articles WHERE BM25(body, 'fast') > 0
 ORDER BY RRF(ANN(body_vec, [0.1, 0.8, 0.1]), BM25(body, 'fast')) LIMIT 5;
  -> InvalidRequest: A query running several searches does not support a WHERE clause

SELECT id FROM demo.articles ORDER BY RRF(1, 2) LIMIT 5;
  -> InvalidRequest: An ORDER BY expression must name at least one search, through ANN() or BM25()

SELECT id FROM demo.articles ORDER BY demo.blend((1.0, 1), (2.0, 2), 0.5) LIMIT 3;
  -> InvalidRequest: An ORDER BY expression must name at least one search, through ANN() or BM25()

SELECT id, BM25_SCORE(title, 'fast') AS s FROM demo.articles ORDER BY ANN(body_vec, [0.1, 0.8, 0.1]) LIMIT 5;
  -> InvalidRequest: BM25_SCORE() in SELECT must match a BM25 search in ORDER BY, with the same column and search term; ORDER BY has no BM25 search
```

## Known limits

- A rescored vector index (`quantization` other than `f32` with `rescoring = 'true'`) reports rank `0`.
- Fused queries take no `WHERE` clause.
- Weighted score orderings such as `0.7 * ANN_SCORE(...) + 0.3 * BM25_SCORE(...)` do not parse yet;
  `ORDER BY` takes a function call, which is why section 7 wraps the arithmetic in a UDF.
- Paging is not supported for external-index queries; the whole result set is returned with a warning
  if the page size is smaller than the limit.
