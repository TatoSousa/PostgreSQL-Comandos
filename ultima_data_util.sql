WITH recs AS (SELECT last_date, CASE WHEN EXTRACT(DOW FROM last_date) IN (0,1) THEN FALSE ELSE TRUE END AS util
  FROM generate_series(current_date-INTERVAL '7days', current_date, interval '1 day') AS g(last_date))
SELECT MAX(last_date) FROM recs WHERE util = TRUE
