## Comandos úteis para Postgresql

### Instalando o Postgresql no Debian

```console
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt update
apt -y install postgresql-{versao}
```

### Instalando o PgAdmin WEB
```console
apt update
apt install -y apt-transport-https ca-certificates software-properties-common curl
curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/pgadmin-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/pgadmin-keyring.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" | tee /etc/apt/sources.list.d/pgadmin4.list
apt update
apt install -y pgadmin4-web

-- Para acessar o ambiente WEB é necessário configurar o seu ambiente
/usr/pgadmin4/bin/setup-web.sh
-- LINK  http://{YOUR_IP_ADDRESS}/pgadmin4
```

### Instalando o PgBadger
```console
apt update
apt install pgbadger
```

- pgbadger -b '2022-01-09 22:00:00' -e '2022-01-10 03:00:00' --appname 'APP ESPECIFICO' /var/log/pg/pg_2022-01-09_*.log -o nomearquivo.html
- pgbadger -o 'arquivo.html' /var/log/pg/pg_2022-01-19_*.log /var/log/pg/pg_2022-01-20_*.log


## Scripts úteis

### Reload das configurações pg_hba.conf
- Verificando se foi executado o pg_reload_conf no postgresql após a alteração do pg_hba.conf
- Executa o Reload a partir do psql
```sql
SELECT pg_conf_load_time() > modification FROM pg_stat_file(current_setting('hba_file'));
SELECT pg_reload_conf();
```

### Conexões ativas no banco
```sql
WITH recs AS (
SELECT current_setting('max_connections') as max_connections,
       COUNT(1) AS open_connections,
       COUNT(1) FILTER (WHERE state IS NULL) AS sys,
       COUNT(1) FILTER (WHERE state = 'idle') AS idle,
       COUNT(1) FILTER (WHERE state = 'idle in transaction') AS in_transaction,
       COUNT(1) FILTER (WHERE state = 'active') AS active
FROM pg_stat_activity)
SELECT max_connections,
       open_connections,
		 sys,
		 idle,
		 in_transaction,
		 active,
		 ROUND(open_connections::decimal(5,0)/max_connections::decimal(5,0),2)*100 AS open_perc
  FROM recs;
```

### Identificando o ultimo dia útil
```sql
WITH recs AS (
SELECT last_date,
       CASE WHEN EXTRACT(DOW FROM last_date) IN (0,1) THEN FALSE ELSE TRUE END AS util
  FROM generate_series(current_date-INTERVAL '7days', current_date, interval '1 day') AS g(last_date))
SELECT MAX(last_date) FROM recs WHERE util = TRUE
```

### Função para converter a timestamp para decimal
```sql
CREATE OR REPLACE FUNCTION f_v_measured_time_base10(p_measured_time INTERVAL, OUT o_measured_time_base10 FLOAT) AS $_$
DECLARE
BEGIN
	--SELECT * FROM f_v_measured_time_base10('08:50:00'::time);
	o_measured_time_base10:=(EXTRACT(EPOCH FROM p_measured_time) / EXTRACT(EPOCH FROM '1:00:00'::INTERVAL));
END;
$_$ LANGUAGE plpgsql IMMUTABLE STRICT;

--ou
SELECT to_char(to_timestamp((12.5) * 60), 'MI:SS');
SELECT EXTRACT(EPOCH FROM '1:00:00'::INTERVAL) --3600

-- Outras opções
SELECT EXTRACT(hour FROM current_timestamp) + EXTRACT(minute FROM current_timestamp)/60.0 as decimal_hours;
SELECT (EXTRACT(hour FROM current_timestamp) + EXTRACT(minute FROM current_timestamp)/60.0) * INTERVAL '1h' as decimal_hours;
```

