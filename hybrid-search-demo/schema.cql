-- Hybrid search demo: schema.
-- One table, two text columns and two vector columns, one index on each, so that the demo can
-- run two full-text searches, two vector searches, or a mix of them in a single SELECT.

CREATE KEYSPACE IF NOT EXISTS demo
  WITH replication = {'class': 'NetworkTopologyStrategy', 'replication_factor': 1}
  AND tablets = {'enabled': true};

CREATE TABLE IF NOT EXISTS demo.articles (
  id        int PRIMARY KEY,
  title     text,
  body      text,
  title_vec vector<float, 3>,   -- toy "embeddings": [databases, animals, cooking]
  body_vec  vector<float, 3>
);

-- Full-text (BM25) indexes.
CREATE CUSTOM INDEX IF NOT EXISTS articles_title_fts ON demo.articles(title) USING 'fulltext_index';
CREATE CUSTOM INDEX IF NOT EXISTS articles_body_fts  ON demo.articles(body)  USING 'fulltext_index';

-- Vector (ANN) indexes. Default quantization (f32) keeps rescoring off, so the Vector Store's own
-- similarity and rank are what the query reports.
CREATE CUSTOM INDEX IF NOT EXISTS articles_title_ann ON demo.articles(title_vec) USING 'vector_index'
  WITH OPTIONS = {'similarity_function': 'cosine'};
CREATE CUSTOM INDEX IF NOT EXISTS articles_body_ann  ON demo.articles(body_vec)  USING 'vector_index'
  WITH OPTIONS = {'similarity_function': 'cosine'};
