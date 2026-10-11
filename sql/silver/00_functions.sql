-- Reusable cleansing functions (persistent UDFs in the silver dataset).

-- Blank / placeholder text -> NULL
CREATE OR REPLACE FUNCTION silver.clean_str(s STRING) RETURNS STRING AS (
  IF(LOWER(TRIM(s)) IN ('', 'na', 'n/a', 'null', 'none', 'unknown', 'xxxxxx'), NULL, TRIM(s))
);

-- Dates arrive as YYYY-MM-DD, DD-Mon-YYYY and NN/NN/YYYY. The slash format mixes
-- DD/MM and MM/DD in the same column, so:
--   second part > 12  -> MM/DD/YYYY (only possible reading)
--   otherwise         -> DD/MM/YYYY (Indian retailer: local convention is the default;
--                        rows where both readings are valid are flagged as ambiguous)
CREATE OR REPLACE FUNCTION silver.parse_date(s STRING) RETURNS DATE AS (
  CASE
    WHEN REGEXP_CONTAINS(TRIM(s), r'^\d{4}-\d{2}-\d{2}$') THEN SAFE.PARSE_DATE('%Y-%m-%d', TRIM(s))
    WHEN REGEXP_CONTAINS(TRIM(s), r'^\d{2}-[A-Za-z]{3}-\d{4}$') THEN SAFE.PARSE_DATE('%d-%b-%Y', TRIM(s))
    WHEN REGEXP_CONTAINS(TRIM(s), r'^\d{2}/\d{2}/\d{4}$') THEN
      IF(CAST(SUBSTR(TRIM(s), 4, 2) AS INT64) > 12,
         SAFE.PARSE_DATE('%m/%d/%Y', TRIM(s)),
         SAFE.PARSE_DATE('%d/%m/%Y', TRIM(s)))
  END
);

-- TRUE when a NN/NN/YYYY date is valid under both DD/MM and MM/DD readings
CREATE OR REPLACE FUNCTION silver.date_is_ambiguous(s STRING) RETURNS BOOL AS (
  IFNULL(
    REGEXP_CONTAINS(TRIM(s), r'^\d{2}/\d{2}/\d{4}$')
    AND CAST(SUBSTR(TRIM(s), 1, 2) AS INT64) <= 12
    AND CAST(SUBSTR(TRIM(s), 4, 2) AS INT64) <= 12
    AND SUBSTR(TRIM(s), 1, 2) != SUBSTR(TRIM(s), 4, 2),
    FALSE)
);

-- '₹2,902.33', '$1,234.50', '73078.38 INR' -> NUMERIC
CREATE OR REPLACE FUNCTION silver.parse_money(s STRING) RETURNS NUMERIC AS (
  SAFE_CAST(NULLIF(REGEXP_REPLACE(s, r'[^0-9.\-]', ''), '') AS NUMERIC)
);

-- Y/yes/true/1 and N/no/false/0 in any case -> BOOL
CREATE OR REPLACE FUNCTION silver.parse_bool(s STRING) RETURNS BOOL AS (
  CASE
    WHEN LOWER(TRIM(s)) IN ('y', 'yes', 'true', 't', '1') THEN TRUE
    WHEN LOWER(TRIM(s)) IN ('n', 'no', 'false', 'f', '0') THEN FALSE
  END
);
