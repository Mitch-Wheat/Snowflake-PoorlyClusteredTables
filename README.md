# Snowflake-PoorlyClusteredTables

Automatically identify all poorly clustered tables across an entire Snowflake account.

https://mitchwheat.com/2026/04/03/snowflake-clustered-tables/

Clustering is probably one of the most misunderstood concepts in Snowflake. Snowflake clustering optimizes query performance on large tables (> 1 terabyte) by organizing data into partitions based on specific keys, enabling efficient partition pruning.

## Clustering Key Recommendations:

- Prioritize Filtering Columns: Choose columns used in WHERE clauses.
- Optimal Cardinality: Aim for a balance. Too few values (e.g., 3-4) or too many (e.g., unique IDs such as UUIDs) won’t prune effectively, and make maintenance costly.
- Date Truncation: Use DATE_TRUNC(‘DAY’, …) on timestamps to group data efficiently rather than clustering by the minute or second.
- Limit Key Length: Use a maximum of 3 or 4 columns per key to avoid high maintenance costs.
- Clustering keys are not intended for all tables due to the costs of initially clustering the data and maintaining the clustering.

## When NOT to Cluster:

- Small tables (< 1TB) that fit into a few micro-partitions.
- Tables without a clear filter pattern.
- Tables that are naturally inserted into in date order.
- Tables with very high update/delete volume (high maintenance overhead).[You should consider Hybrid tables for these.]

Snowflake ref.: (https://docs.snowflake.com/en/user-guide/tables-clustering-keys)
