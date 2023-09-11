--Database  size + Xid + Fragmentacao - porta - versao
SELECT pg_database.datname,
       case when pg_database.datallowconn = true THEN 'YES' ELSE 'NO' END  AS is_allow_conn,
       age(pg_database.datfrozenxid) AS datfrozenxid,
		 pg_size_pretty(pg_database_size(pg_database.datname)) as db_size,
		 pg_database_size(pg_database.datname) AS db_size_bytes,
		 conexoes.quantity as total_conn,
		 case when coalesce(idle_transaction.quantity,0) >0 THEN 'YES' ELSE 'NO' END AS is_idle_in_transaction_5_minutes,
		 pg_database.datcollate,
		 inet_server_addr() as ip,
		 current_setting('port') as porta
FROM pg_database
LEFT JOIN (SELECT datname, COUNT(*) AS quantity FROM pg_stat_activity GROUP BY datname) AS conexoes ON pg_database.datname = conexoes.datname
LEFT JOIN (SELECT datname, COUNT(*) AS quantity FROM pg_stat_activity WHERE state = 'idle in transaction' AND now() - state_change > '5 minutes'
			  GROUP BY datname) AS idle_transaction ON pg_database.datname = conexoes.datname;

--Atraso na replicacao
select
	NOW(),
	pid,
	pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)) as sent_lag_size,
	pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) as replay_lag_size,
	replay_lag,
	write_lag,
	flush_lag 
from pg_stat_replication;

--Processos em execução
SELECT now() - state_change AS elapsed_time,
       pid,
		 leader_pid,
		 state,
		 datname,
		 usename,
		 application_name,
		 backend_type, 
		 CONCAT(wait_event, '/', wait_event_type) as event, query
  FROM pg_stat_activity
  ORDER BY CASE
               WHEN state = 'active' THEN 1
					WHEN state = 'idle in transaction' THEN 0
					ELSE 3
				END ASC , elapsed_time DESC, coalesce(leader_pid,pid), pid

-- XID tables
SELECT c.oid::regclass AS table_name,
       age(c.relfrozenxid) AS relfrozenxid,
		 CASE 
		     WHEN relkind = 'r' THEN 'TABLE'
		     WHEN relkind = 'i' THEN 'INDEX'
		     WHEN relkind = 'S' THEN 'SEQUENCE'
		     WHEN relkind = 't' THEN 'TOAST'
		     WHEN relkind = 'v' THEN 'VIEW'
		     WHEN relkind = 'm' THEN 'MATERIALIZED VIEW'
		     WHEN relkind = 'c' THEN 'composite type'
		     WHEN relkind = 'f' THEN 'foreign table'
		     WHEN relkind = 'p' THEN 'PARTIÇÃO'
		     WHEN relkind = 'I' THEN 'partitioned index'
		END as kind,
		last_vacuum,
		last_analyze,
		CONCAT('VACUUM VERBOSE ANALYSE ', c.oid::regclass,';')
FROM pg_class AS c
JOIN pg_namespace n ON c.relnamespace = n.oid
LEFT JOIN pg_stat_user_tables u ON c.oid = u.relid
WHERE relkind IN ('r', 't', 'm') AND age(c.relfrozenxid) > 100000000
ORDER BY age(c.relfrozenxid) DESC;

--Fragmentacao
SELECT ' % Fragmentação'::text as table_name, 0 as ordenacao,
       COALESCE( round(((sum(n_dead_tup) * 100)) / sum(n_live_tup), 4), 0)  as sql_deadtuples_pec
		 from pg_stat_all_tables where n_live_tup > 0
UNION
SELECT relid::regclass::Text AS tables_name, 1 as ordenacao,
       COALESCE( round(((n_dead_tup * 100)) / n_live_tup, 2), 0)  as sql_deadtuples_pec from pg_stat_all_tables where n_live_tup > 0
ORDER BY ordenacao, sql_deadtuples_pec DESC
LIMIT 20;

--Blocking
SELECT blocked_locks.pid AS blocked_pid,
		blocked_activity.usename AS blocked_user,
		blocking_locks.pid AS blocking_pid,
		blocking_activity.usename AS blocking_user,
		blocked_activity.query AS blocked_statement,
		blocking_activity.query AS current_statement_in_blocking_process,
		blocked_activity.application_name AS blocked_application,
		blocking_activity.application_name AS blocking_application,
		blocked_activity.datname AS blocked_datname,
		blocking_activity.datname AS blocking_datname
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
					ON blocking_locks.locktype = blocked_locks.locktype
						AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
						AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
						AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
						AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
						AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
						AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
						AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
						AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
						AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
						AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

--Bloated

select relid::regclass::Text AS tables_name,bloat AS bloat_perc, reltuples, relpages, pg_size_pretty(wastedbytes) as wasted
from (
        select relid,
            schemaname,
            tablename,
            case
                when otta = 0 then 0.0
                else sml.relpages / otta::numeric
            end as bloat,
            reltuples::bigint,
            relpages::bigint,
            otta,
            (bs * otta)::bigint as expbytes,
            case
                when relpages < otta then 0
                else(bs *(sml.relpages - otta))::bigint
            end as wastedbytes,
            case
                when relpages < otta then 0
                else relpages::bigint - otta
            end as wastedpages,
            (bs * relpages)::bigint as relbytes
        from(
                select schemaname,
                    tablename,
                    cc.oid as relid,
                    cc.reltuples,
                    cc.relpages,
                    bs,
                    ceil(
                        (
                            cc.reltuples *(
                                (
                                    datahdr + ma -(
                                        case
                                            when datahdr %ma = 0 then ma
                                            else datahdr %ma
                                        end
                                    )
                                ) + nullhdr2 + 4
                            )
                        ) /(bs -20::float)
                    ) as otta
                from (
                        select ma,
                            bs,
                            schemaname,
                            tablename,
                            (
                                datawidth +(
                                    hdr + ma -(
                                        case
                                            when hdr %ma = 0 then ma
                                            else hdr %ma
                                        end
                                    )
                                )
                            )::numeric as datahdr,
                            (
                                maxfracsum *(
                                    nullhdr + ma -(
                                        case
                                            when nullhdr %ma = 0 then ma
                                            else nullhdr %ma
                                        end
                                    )
                                )
                            ) as nullhdr2
                        from (
                                select schemaname,
                                    tablename,
                                    hdr,
                                    ma,
                                    bs,
                                    sum((1 - s.null_frac) * avg_width) as datawidth,
                                    max(s.null_frac) as maxfracsum,
                                    hdr +(
                                        1 +(
                                            count(
                                                case
                                                    when s.null_frac <> 0 then 1
                                                end
                                            )
                                        ) / 8
                                    ) as nullhdr
                                from pg_stats s
                                    cross join (
                                        select current_setting('block_size')::numeric as bs,
                                            case
                                                when substring(version(), 12, 3) in ('8.0', '8.1', '8.2') then 27
                                                else 23
                                            end as hdr,
                                            case
                                                when version() ~ 'mingw32' then 8
                                                else 4
                                            end as ma
                                    ) as constants
                                group by schemaname,
                                    tablename,
                                    hdr,
                                    ma,
                                    bs
                            ) as foo
                    ) as rs
                    join pg_class cc on cc.relname = rs.tablename
                    and cc.relkind = 'r'
                    join pg_namespace nn on cc.relnamespace = nn.oid
                    and nn.nspname = rs.schemaname
            ) as sml
    ) as wrapper
where wastedbytes > 2 * 1024 * 1024
    and bloat >= 3
	 ORDER BY bloat_perc;

-- Indices sem utilização
SELECT
    relname,
    indexrelname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelname::regclass)) as size
FROM
    pg_stat_all_indexes
WHERE
    schemaname = 'public'
    AND indexrelname NOT LIKE 'pg_toast_%'
    AND idx_scan = 0
    AND idx_tup_read = 0
    AND idx_tup_fetch = 0
ORDER BY
    pg_relation_size(indexrelname::regclass) DESC;

-- Indice Invalido

SELECT
    c.relname as index_name,
    pg_size_pretty(pg_relation_size(c.oid))
FROM
    pg_index i
    JOIN pg_class c ON i.indexrelid = c.oid
WHERE
    -- New index built using REINDEX CONCURRENTLY
    c.relname LIKE  '%_ccnew'
    -- In INVALID state
    AND NOT indisvalid
LIMIT 10;

-- Find indexed columns with high null_frac
SELECT
    c.oid,
    c.relname AS index,
    pg_size_pretty(pg_relation_size(c.oid)) AS index_size,
    i.indisunique AS unique,
    a.attname AS indexed_column,
    CASE s.null_frac
        WHEN 0 THEN ''
        ELSE to_char(s.null_frac * 100, '999.00%')
    END AS null_frac,
    pg_size_pretty((pg_relation_size(c.oid) * s.null_frac)::bigint) AS expected_saving
    -- Uncomment to include the index definition
    --, ixs.indexdef
FROM
    pg_class c
    JOIN pg_index i ON i.indexrelid = c.oid
    JOIN pg_attribute a ON a.attrelid = c.oid
    JOIN pg_class c_table ON c_table.oid = i.indrelid
    JOIN pg_indexes ixs ON c.relname = ixs.indexname
    LEFT JOIN pg_stats s ON s.tablename = c_table.relname AND a.attname = s.attname

WHERE
    NOT i.indisprimary    -- Primary key cannot be partial
    AND i.indpred IS NULL -- Exclude already partial indexes
   AND array_length(i.indkey, 1) = 1    -- Exclude composite indexes
   AND pg_relation_size(c.oid) > 10 * 1024 ^ 2     -- Larger than 10MB
 ORDER BY
    pg_relation_size(c.oid) * s.null_frac DESC;

--Listagem de acessos
WITH members AS ( WITH RECURSIVE cte AS ( SELECT oid, rolname FROM pg_roles UNION ALL
										 SELECT m.roleid, rolname FROM cte JOIN pg_auth_members m ON m.member = cte.oid
				   ) SELECT rolname, string_agg(oid::regrole::text,', ') AS rolename
				  FROM cte
				  WHERE rolname NOT ILIKE 'pg%'
				  GROUP BY 1 ORDER BY 1),
   acessos AS (SELECT u.usename,
			          u.usesuper,
			          r.table_catalog,
					  r.privilege_type
				  FROM information_schema.role_table_grants AS r
			 LEFT JOIN pg_catalog.pg_user AS u ON u.usename = r.grantee
			 LEFT JOIN information_schema.tables AS t ON t.table_schema = r.table_schema AND t.table_name = r.table_name
			 LEFT JOIN pg_tables AS tab ON tab.schemaname = r.table_schema AND tab.tablename = r.table_name
			 LEFT JOIN pg_catalog.pg_class pgc ON t.table_name = pgc.relname 	
				 WHERE r.table_schema NOT IN ('pg_catalog', 'information_schema')
			  GROUP BY u.usename,
			           u.usesuper,
			           r.table_catalog,
					   r.privilege_type
			  ORDER BY u.usename,
			           u.usesuper,
			           r.table_catalog,
					   r.privilege_type
			  )
SELECT m.rolname,
       m.rolename,
	   CASE WHEN COALESCE(u.usesuper, a.usesuper, false) = false THEN 'NO' ELSE 'YES' END AS usesuper,
	   CONCAT(inet_server_addr(),'/',current_database()) AS table_catalog,
	   string_agg(a.privilege_type, ' ') as privilege
  FROM members AS m
LEFT JOIN acessos AS a ON a.usename = m.rolname
LEFT JOIN pg_catalog.pg_user AS u ON u.usename = m.rolname
GROUP BY m.rolname,
       m.rolename,
	   3,
	   a.table_catalog
ORDER BY usesuper DESC, m.rolname;
