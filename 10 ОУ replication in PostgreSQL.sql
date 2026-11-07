gcloud beta compute --project=celtic-house-266612 instances create postgres4 --zone=us-central1-a --machine-type=e2-small --subnet=default --network-tier=PREMIUM --maintenance-policy=MIGRATE --service-account=compute-service-account@celtic-house-266612.iam.gserviceaccount.com --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --boot-disk-size=100GB --boot-disk-type=pd-ssd --boot-disk-device-name=postgres4 --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

gcloud compute ssh postgres4

-- 2 window
gcloud beta compute --project=celtic-house-266612 instances create postgres4r --zone=us-central1-a --machine-type=e2-small --subnet=default --network-tier=PREMIUM --maintenance-policy=MIGRATE --service-account=compute-service-account@celtic-house-266612.iam.gserviceaccount.com --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --boot-disk-size=50GB --boot-disk-type=pd-ssd --boot-disk-device-name=postgres4 --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

gcloud compute ssh postgres4r

sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt -y install postgresql-18 unzip atop iotop

gcloud compute instances list

-- поднимаем реплику - тестируем
-- 1 node
sudo su postgres 
cd ~
cat >> /etc/postgresql/18/main/postgresql.conf << EOL
listen_addresses = '10.128.0.8'
EOL
-- sudo pg_conftool 17 main13 set listen_addresses '*' - с адресом НЕ работает !!! кавычек не ставит и не воспринимается
cat >> /etc/postgresql/18/main/pg_hba.conf << EOL
host replication replicator 10.128.0.0/16 scram-sha-256
EOL
-- стоп и старт кластера под юзером postgres, ибо запущен был под суперюзером и restart не сработает
pg_ctlcluster 18 main stop && pg_ctlcluster 18 main start

-- зальём тайские перевозки
wget https://storage.googleapis.com/thaibus/thai_small.tar.gz && tar -xf thai_small.tar.gz && psql < thai.sql

-- создадим пользователя для репликации. НЕ используем postgres
-- обратим внимание на возможные проблемы экранирования спецсимволов при командном исполнении
psql -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'secret$123';"
--psql -c "ALTER USER replicator WITH PASSWORD 'secret\$123';"

-- создадим слот для устойчивости
psql -c "SELECT pg_create_physical_replication_slot('test');"

-- 2 cluster
sudo su postgres
-- format hostname:port:database:username:password and supports wildcards, so you can just set the database to "*" for example.
cat >> ~/.pgpass << EOL
postgres4:5432:*:replicator:secret$123
EOL

-- выдадим нужные права для секьюрности
chmod 0600 ~/.pgpass

pg_ctlcluster 18 main stop
rm -rf /var/lib/postgresql/18/main
pg_basebackup -h postgres4 -p 5432 -U replicator -R -S test -D /var/lib/postgresql/18/main

-- если висит, ожидает checkpoint
checkpoint;

-- тестируем
-- нагрузка на запись
cat > ~/workload2.sql << EOL
INSERT INTO book.tickets (fkRide, fio, contact, fkSeat)
VALUES (
	ceil(random()*100)
	, (array(SELECT fam FROM book.fam))[ceil(random()*110)]::text || ' ' ||
    (array(SELECT nam FROM book.nam))[ceil(random()*110)]::text
    ,('{"phone":"+7' || (1000000000::bigint + floor(random()*9000000000)::bigint)::text || '"}')::jsonb
    , ceil(random()*100));

EOL
------------------------------------
-- for 18 PG
/usr/lib/postgresql/18/bin/pgbench -c 8 -j 4 -T 10 -f ~/workload2.sql -n -U postgres -p 5432 thai
-- 3500

-- нагрузка на чтение
cat > ~/workload.sql << EOL

\set r random(1, 5000000) 
SELECT id, fkRide, fio, contact, fkSeat FROM book.tickets WHERE id = :r;

EOL
------------------------------------
-- for 18 PG
/usr/lib/postgresql/18/bin/pgbench -c 8 -j 4 -T 10 -f ~/workload.sql -n -U postgres thai
--18000

-- start 2
pg_ctlcluster 18 main start

psql -d thai -c "select pg_is_in_recovery();"

psql -d thai -c "select count(*) from book.tickets;"

-- тестируем на запись
-- 2500
-- если включить синхронный коммит, падение будет более драматическим

-- тестируем на чтение мастера
-- 11000

-- тестируем на чтение слейва
-- 11000
-- в целом небольшая погрешность

-- обратите внимание, что несмотря на то, что включен синхронный коммит, реплика НЕ настроена правильно
-- !!!! нужно корректно настроить application_name на реплике !!!!!
-- !!!! и synchronous_standby_names на мастере !!!!
psql -c "SHOW synchronous_commit;"
psql -c "ALTER SYSTEM SET synchronous_commit='remote_apply';"

-- Проверим состояние репликации:
SELECT * FROM pg_stat_replication \gx

-- sync_state       | async


Посмотрим на процессы реплики:
ps -o pid,command --ppid `head -n 1 /var/lib/postgresql/18/main/postmaster.pid`
 PID COMMAND
  848 postgres: 18/main: startup process   recovering 00000001000000000000000B
  849 postgres: 18/main: checkpointer process
  850 postgres: 18/main: writer process
  851 postgres: 18/main: stats collector process
  852 postgres: 18/main: wal receiver process   streaming 0/B002290
Процесс wal receiver принимает поток журнальных записей, процесс startup применяет изменения.

Сравним с процессами мастера:
ps -o pid,command --ppid `head -n 1 /var/lib/postgresql/18/main/postmaster.pid`
  PID COMMAND
  853 postgres: 18/main: wal sender process postgres [local] streaming 0/B002290
10430 postgres: 18/main: checkpointer process
10431 postgres: 18/main: writer process
10432 postgres: 18/main: wal writer process
10433 postgres: 18/main: autovacuum launcher process
10434 postgres: 18/main: stats collector process
10435 postgres: 18/main: bgworker: logical replication launcher

-- кворум можно настроить для репликации
-- https://wiki.postgresql.org/wiki/New_in_postgres_10#Quorum_Commit_for_Synchronous_Replication

psql -d thai -c "ALTER SYSTEM SET synchronous_commit='off';"
pg_ctlcluster 18 main reload

-- запромоутим реплику
pg_ctlcluster 18 main promote

psql -d thai -c "select pg_is_in_recovery();"
-- f - теперь самостоятельный мастер

ls -la
-rw-------  1 postgres postgres      0 Mar 25 16:59 standby.signal

-- Логическая репликация
psql -d thai -c "ALTER SYSTEM SET wal_level = logical;"

-- Рестартуем кластер
pg_ctlcluster 18 main restart


-- На первом сервере создаем публикацию:
psql
CREATE TABLE test(i int);
CREATE PUBLICATION test_pub FOR TABLE test;
\password 
-- admin$123
\dRp+

-- создадим подписку на втором экземпляре
CREATE TABLE test(i int);
--создадим подписку к БД по Порту с Юзером и Паролем и Копированием данных=false
CREATE SUBSCRIPTION test_sub 
CONNECTION 'host=10.128.0.8 port=5432 user=postgres password=admin$123 dbname=postgres' 
PUBLICATION test_pub WITH (copy_data = false);

-- ERROR:  could not connect to the publisher: connection to server at "10.128.0.25", port 5432 failed: FATAL:  no pg_hba.conf entry for host "10.128.0.17", user "postgres", database "postgres", SSL encryption
-- connection to server at "10.128.0.25", port 5432 failed: FATAL:  no pg_hba.conf entry for host "10.128.0.17", user "postgres", database "postgres", no encryption

nano /etc/postgresql/18/main/pg_hba.conf
-- а настраивали то только для replicator

cat >> /etc/postgresql/18/main/pg_hba.conf << EOL
host postgres postgres 10.128.0.0/16 scram-sha-256
EOL

pg_ctlcluster 18 main reload

-- Теперь подписка создалась
\dRs

SELECT * FROM pg_stat_subscription \gx

--добавим одинаковые данные
insert into test values (1);
insert into test values (1);

---добавить индекс на 1
CREATE unique index on test (i);
truncate test;
\dS+ test

-- обратите внимание, индекс не доедет до подписки! ручное создание


-- если нужно удалить публикацию/подписку
-- drop publication test_pub;
-- drop subscription test_sub;


gcloud compute instances delete postgres4
gcloud compute instances delete postgres4r