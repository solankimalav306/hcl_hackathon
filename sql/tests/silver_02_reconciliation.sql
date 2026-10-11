-- No row disappears silently: bronze = silver + removed duplicates + merged + quarantined.
SELECT * FROM silver.dq_table_summary WHERE NOT balanced
