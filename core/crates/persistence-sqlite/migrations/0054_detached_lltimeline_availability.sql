-- Historical detached LLTimeline imports used a synthetic path while claiming
-- the media was available. Only that synthetic namespace is safe to identify
-- automatically; real-looking path snapshots need an explicit future attach
-- workflow instead of filesystem guesses during migration.
UPDATE media_items
SET availability = '"missing"'
WHERE availability = '"available"'
  AND path LIKE 'lltimeline://%';
