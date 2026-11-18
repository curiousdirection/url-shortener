# 5. Generate short codes from a Postgres sequence, not a Redis counter

Date: 2026-11-18. Status: accepted. Records a decision made in [#3](https://github.com/curiousdirection/url-shortener/pull/3) (2026-11-11); the reasons beyond #3's own came from a later review.

## Context

A generated short code is a number, base62-encoded. The number must be unique, and a number that has been used for a link must never be handed out again. The first version took it from Redis (`INCR`).

## Decision

Take the number from a Postgres sequence (`nextval('url_code_seq')`) in the same database as the `urls` table.

## Why

- **One service on the create path.** Creating a link needs only Postgres. With Redis, a create fails if either Redis or Postgres is down. (This was #3's reason.)
- **The counter can't go backwards.** Postgres acknowledges a commit only after it is in its write-ahead log (and, with Multi-AZ, on the standby). After a crash it may skip a few numbers, but never reissues one that a stored link uses. Redis answers `INCR` from memory and copies it to disk and replicas afterwards, so a failover can rewind the counter, and a restart without persistence resets it to 0. Reissued numbers collide with existing codes; the primary key stops a link being overwritten, but every create then fails its retries until someone fixes the counter by hand.
- **Counter and links share fate.** They live in the same database and the same backups, so a restore puts both back to the same moment. A separate counter can be restored, reset or lost on its own.
- **Load is not a reason for Redis.** At full scale creates average about 115/s. The `INSERT` that follows each `nextval` is the heavier part, and a separate counter wouldn't remove it.

## Consequences

- **Codes have gaps** (failed inserts, crashes). Nothing relies on them being gapless.
- **Code generation is tied to Postgres.** Moving the links to another database means choosing a new scheme (see the alternatives).

## Alternatives considered

- **Redis `INCR`** (the first version): see above.
- **MemoryDB**, a Redis-compatible store with a durable transaction log: fixes the rewind, but still adds a second service to every create.
- **Random codes, inserted only if free:** no counter at all. Codes would be 7 characters instead of 6 at 1 billion links, and a create occasionally retries.
- **Block allocation** (each instance reserves 1,000 numbers at a time): only needed when one counter can't keep up with creates.

## Revisit when

Creates approach what one Postgres primary can insert, or the links move off Postgres.
