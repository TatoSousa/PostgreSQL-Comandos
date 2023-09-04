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

## Scripts úteis
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
		 ROUND(open_connections/max_connections,2) AS open_perc
  FROM recs;
```
