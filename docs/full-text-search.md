# Full-text search

`database` provides Ada-native full-text search for Unicode text columns without SQL syntax, a parser, reflection, or an external search engine.

## Index model

A full-text index maps a normalized term to a posting list. A posting records the table id, stable row identity, exact row identity key, column id, frequency, token positions, and MVCC creation/deletion metadata. For schemas with primary-key metadata, the row identity is derived from primary-key values rather than from the row position in the in-process catalog cache. The first implementation keeps the public model explicit and exposes row references plus deterministic scores through `Database.Full_Text.Search_Cursor`.

## Creating an index

```ada
Database.Transactions.Begin_Write (DB, Tx);
Result := Database.Full_Text.Create_Full_Text_Index
  (Tx         => Tx,
   Name       => "docs_body_ft",
   Table_Name => "docs",
   Column     => 1);
```

Opt-in simple English stemming uses the Boolean overload:

```ada
Result := Database.Full_Text.Create_Full_Text_Index
  (Tx                      => Tx,
   Name                    => "docs_body_ft_stemmed",
   Table_Name              => "docs",
   Column                  => 1,
   Simple_English_Stemming => True);
```

The indexed column must exist and must be `Database.Types.Text_Value`. Duplicate full-text index names are rejected with `Already_Exists`; invalid columns are rejected through status results, not ordinary exceptions.

## Query object API

Queries are strongly typed values from `Database.Full_Text.Queries`:

```ada
Q := Database.Full_Text.Queries.And_
  (Database.Full_Text.Queries.Term ("ada"),
   Database.Full_Text.Queries.Prefix ("transact"));

Cursor := Database.Full_Text.Search (Tx, "docs_body_ft", Q);
```

Supported query forms are term, Boolean AND/OR/NOT, phrase, prefix, NEAR, fuzzy edit-distance matching, and match-all. String helpers only construct typed query objects; there is no SQL-like full-text query parser.

## Tokenization

`Database.Full_Text.Tokenizers` provides the initial `Unicode_Whitespace` tokenizer. It treats Unicode whitespace as separators and, by default, treats punctuation as separators. Tokens preserve their zero-based token position and character offsets. Future tokenizers can be added without changing the query API.

The tokenizer also exposes opt-in filtering controls: `Minimum_Token_Length`, `Drop_Builtin_Stop_Words`, and `Builtin_Stop_Words`. Built-in stop-word profiles are deliberately small and deterministic; currently English, Danish, German, and French profiles are available. Filtering is disabled by default. When filtering is enabled, emitted tokens keep their original token positions rather than being renumbered, so positional queries remain tied to the source text. Applications that need deeper linguistic analysis should register a custom tokenizer.

## Normalization

`Database.Full_Text.Normalization` performs conservative matching normalization. By default it lowercases ASCII, Latin-1, and common Latin Extended uppercase code points where one-code-point lowercase mappings keep offsets stable, and it preserves accents. Optional basic Latin and Latin Extended accent stripping is exposed for deterministic matching. A simple English stemmer is also available when the index is created through the stemming-enabled `Create_Full_Text_Index` overload; it handles common suffixes such as `s`, `ies`, `ing`, and `ed`, and is deliberately not a locale-aware morphology engine or full Unicode collation.

## Ranking

Ranking is deterministic and uses a small BM25-style formula when the index can provide enough statistics:

```text
idf ~= (total_documents + 1) / (document_frequency + 1)
score = idf * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * document_length / average_document_length)))
```

`k1 = 1.2` and `b = 0.75`. The implementation deliberately uses a monotonic positive IDF approximation rather than claiming a production IR ranker. Query scoring adds a small matched-term contribution and a phrase bonus for phrase searches. Equal scores are ordered deterministically by stable row identity key.

For relational query pipelines, `Database.Queries.Full_Text_Search_With_Score` and `Try_Full_Text_Search_With_Score` return each matched row with one trailing `Float_Value` score column. Callers can then use the existing Ada-native `Order_By` and `Limit` operations to express ranked result pages without introducing SQL or a string parser.

## MVCC, WAL, recovery, vacuum, and check

Full-text postings carry transaction/version metadata so search cursors can avoid exposing obsolete entries. Table insert/update/delete hooks update full-text indexes through the same transaction-scoped API as other table mutations. Posting references are based on stable row identity keys, so deleting one row does not shift posting references for later rows. Persistent full-text definitions are stored in the main database catalog extension. Posting lists are stored in a `<database>.fts` cache, but persistent open treats the cache as rebuildable and regenerates postings from catalog definitions plus current table rows when definitions are present. Integrity and diagnostics expose full-text term/posting counts so check and vacuum tooling can validate and compact obsolete postings. `Database.Full_Text.Segments` exposes an explicit segment compaction policy for deterministic merge decisions based on active segment count and obsolete posting pressure.

## Limitations

- No SQL full-text syntax.
- No parser.
- No external search engine.
- Stemming is optional and intentionally simple; it is not locale-aware and does not replace custom tokenizer/normalizer extensions for language-specific analysis.
- Fuzzy search is implemented as bounded Levenshtein edit distance over normalized terms; it is intentionally not phonetic or language-aware.
- Unicode behavior is documented conservatively; the implementation does not claim full Unicode collation.


## Maintenance Semantics

Full-text postings carry creation and deletion transaction metadata. Search filters postings through the caller transaction snapshot. A posting created by the caller is visible to that caller, committed postings are visible only when their creation version is in the caller snapshot, and rolled-back postings are ignored. Deleted postings are hidden from the deleting transaction immediately and hidden from later snapshots only after the deleting transaction commits.

Table `Insert`, `Update`, and `Delete` operations maintain full-text indexes through the transaction object. `Update` is modeled as delete plus insert, so old terms are obsoleted and new terms receive fresh posting metadata. Phrase queries require adjacent token positions; a row containing both terms in a different order does not satisfy a phrase query.

Current persistence boundary: full-text postings use the in-crate inverted index representation and a `<database>.fts` sidecar. Definitions are persisted in the main catalog; postings are cached in `<database>.fts`. On persistent open, definitions are treated as authoritative and postings are rebuilt from the catalog and current table rows, then the posting cache is refreshed. This makes the posting sidecar rebuildable after a stale/missing cache and avoids trusting postings that may have diverged from the main database/WAL state. Hardening checks treat catalog definitions as authoritative and validate or rebuild posting structures during open/check paths, so stale or corrupted sidecar state is not trusted as durable truth.

`Database.Full_Text.Vacuum_Index` compacts reclaim-safe deleted postings and rebuilds document statistics from the surviving live postings. Segment-level callers can use `Needs_Compaction` and `Compact_With_Policy` to merge sealed segments once active segment count or obsolete-posting ratio crosses a configured threshold.

## Persistent row resolution

Executable query integration resolves full-text hits through `Database.Full_Text.Resolve_Row`. For persistent databases this scans the MVCC-visible table heap owned by the transaction and compares the stored stable row identity key, rather than relying on the transient catalog row registry. This is important after reopening a database: the row cache can be empty, but the table heap is authoritative. In-memory databases still use the catalog row registry.

Creating a full-text index on an existing persistent table also scans the table heap first. The catalog row registry is used only as a fallback for in-memory tables or schemas without persistent heap pages.

## Status-returning query integration

`Database.Full_Text.Search` and `Database.Queries.Full_Text_Search` remain convenience helpers that return an empty cursor/query on ordinary search failure. Production code should prefer the status-returning variants:

```ada
Result := Database.Full_Text.Try_Search (Tx, "docs_body_ft", Q, Cursor);
Result := Database.Queries.Try_Full_Text_Search (Tx, "docs_body_ft", Q, Query_Result);
```

These variants report missing indexes and row-resolution failures through `Database.Status.Result`, preserving the project rule that ordinary database failures are not represented by exceptions.


## Advanced query helpers added in the hardening pass

`Database.Full_Text.Queries.Near (Left, Right, Max_Distance)` matches rows where both terms occur within the requested token distance. It is positional and uses the same posting positions as phrase search. `Database.Full_Text.Queries.Fuzzy (Text, Max_Edit_Distance)` scans normalized dictionary terms and unions posting lists whose edit distance is within the requested bound. This is correct for small dictionaries and tests, but it is not optimized for very large dictionaries.

`Database.Full_Text.Snippets.Generate` can produce a bounded Wide_Wide_String snippet around the first matched term. It operates on Ada `Wide_Wide_Character` boundaries and does not split code points. It also avoids cutting adjacent Unicode combining-mark sequences at snippet and marker boundaries.

Full-text WAL records support page-granular redo and undo images for native dictionary and posting pages. Recovery applies committed full-text redo images, applies uncommitted full-text undo images, and rejects full-text WAL images whose payload is not a full-text page. Posting positions already use gap/varint encoding, and `Database.Full_Text.Postings` exposes skip-table helpers for sorted posting-list intersections.


## Native full-text page encoding

Full-text payloads are stored using explicit native page helpers rather than Ada record memory layout. The native page format is versioned and uses two page families:

- `Full_Text_Dictionary_Page` maps a normalized term to the posting-page root.
- `Full_Text_Posting_Page` stores postings for one term and may chain to a following posting page.

Posting positions are encoded with base-128 varints and gap encoding. This keeps the on-page representation deterministic, portable, and checkable. For large sorted posting lists, `Build_Skip_Table` and `Intersect_With_Skips` provide explicit skip-pointer acceleration. The ordinary `Intersect` operation remains order-agnostic for correctness; callers should use the skip variant only when they maintain sorted posting lists. The encoding is intentionally simple and does not rely on external libraries.

The page helpers are exposed through `Database.Full_Text.Storage`; low-level gap/varint helpers are exposed through `Database.Full_Text.Compression` for tests, diagnostics, and integrity checking.

## Document statistics

The index now maintains per-document statistics alongside term postings. For each indexed row it records the stable row identity key and the number of emitted tokens after tokenizer filtering. Ranking uses the live document count, per-term document frequency, each matched document length, and average document length rather than treating posting count as document count. This keeps BM25-style ranking deterministic and prevents repeated terms in a single row from inflating corpus-level document frequency.

Deletes mark the document statistic entry obsolete together with the postings. Vacuum/rebuild paths can recompute these statistics from the authoritative table rows and full-text catalog definitions.
