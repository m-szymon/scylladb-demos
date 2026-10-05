-- Hybrid search demo: eight articles across three topics.
-- The word "fast" appears in database, animal and cooking rows alike, and "lazy dog" in one animal
-- and one cooking row, so text search and vector search deliberately disagree.
-- Vectors are hand-made 3-dim "embeddings" on the axes [databases, animals, cooking].

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (1,
  'ScyllaDB is a fast distributed database',
  'ScyllaDB is a distributed NoSQL database built for low latency. It is fast because every shard owns its own memory and I/O, and tablets move data between nodes without downtime.',
  [0.9, 0.2, 0.0], [0.9, 0.1, 0.0]);

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (2,
  'Vector search in ScyllaDB',
  'Vector search finds the rows whose embeddings are nearest to a query vector. The Vector Store indexes them with HNSW and answers ANN queries for the database.',
  [0.8, 0.0, 0.1], [0.9, 0.0, 0.05]);

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (3,
  'The quick brown fox',
  'The quick brown fox jumps over the lazy dog. Foxes are fast and clever hunters that live at the edge of the forest.',
  [0.1, 0.9, 0.0], [0.1, 0.9, 0.0]);

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (4,
  'Wombats dig fast',
  'A wombat digs its burrow surprisingly fast for such a stocky animal. Wombats are nocturnal marsupials from Australia.',
  [0.0, 0.9, 0.1], [0.0, 1.0, 0.0]);

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (5,
  'Fast weeknight pasta',
  'A fast pasta recipe: garlic, olive oil and chili with spaghetti. Dinner in fifteen minutes.',
  [0.0, 0.1, 0.9], [0.0, 0.05, 1.0]);

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (6,
  'Baking sourdough bread',
  'Sourdough needs a lively starter, patience and a hot oven. Slow fermentation is what gives the crust its flavor.',
  [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]);

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (7,
  'Database indexes explained',
  'An index speeds up lookups in a database. A full-text index ranks documents with BM25, while a vector index ranks them by similarity to a query.',
  [0.9, 0.0, 0.1], [0.8, 0.0, 0.2]);

INSERT INTO demo.articles (id, title, body, title_vec, body_vec) VALUES (8,
  'Cooking for a lazy dog',
  'Homemade dog food: rice, chicken and carrots simmered together. Even a lazy dog gets excited about this dinner.',
  [0.1, 0.4, 0.5], [0.0, 0.5, 0.6]);
