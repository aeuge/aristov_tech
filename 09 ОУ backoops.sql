-- Ubuntu 24.04 LTS + PostgreSQL 18
gcloud beta compute --project=celtic-house-266612 instances create postgres --zone=us-central1-a --machine-type=e2-medium --subnet=default --network-tier=PREMIUM --maintenance-policy=MIGRATE --service-account=compute-service-account@celtic-house-266612.iam.gserviceaccount.com --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud --boot-disk-size=20GB --boot-disk-type=pd-ssd --boot-disk-device-name=postgres4 --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

gcloud compute ssh postgres

sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt -y install postgresql-18 unzip atop iotop

sudo su postgres
 
-- конфиг с калькулятора
cat >> /etc/postgresql/18/main/postgresql.conf << EOL
shared_buffers = '4096 MB'
work_mem = '32 MB'
maintenance_work_mem = '320 MB'
huge_pages = off
effective_cache_size = '11 GB'
effective_io_concurrency = 100 # concurrent IO only really activated if OS supports posix_fadvise function
random_page_cost = 1.1 # speed of random disk access relative to sequential access (1.0)

# Monitoring
shared_preload_libraries = 'pg_stat_statements'    # per statement resource usage stats
track_io_timing=on        # measure exact block IO times
track_functions=pl        # track execution times of pl-language procedures if any

# Replication
wal_level = replica		# consider using at least 'replica'
max_wal_senders = 0
synchronous_commit = on

# Checkpointing: 
checkpoint_timeout  = '15 min' 
checkpoint_completion_target = 0.9
max_wal_size = '1024 MB'
min_wal_size = '512 MB'

# WAL writing
wal_compression = on
wal_buffers = -1    # auto-tuned by Postgres till maximum of segment size (16MB by default)
wal_writer_delay = 200ms
wal_writer_flush_after = 1MB

# Background writer
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0
bgwriter_flush_after = 0

# Parallel queries: 
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_maintenance_workers = 2
max_parallel_workers = 4
parallel_leader_participation = on

# Advanced features 
enable_partitionwise_join = on 
enable_partitionwise_aggregate = on
jit = on
max_slot_wal_keep_size = '1000 MB'
track_wal_io_timing = on
maintenance_io_concurrency = 100
EOL

pg_ctlcluster 18 main stop && pg_ctlcluster 18 main start

-- зальём тайские перевозки
cd ~ && wget https://storage.googleapis.com/thaibus/thai_small.tar.gz && tar -xf thai_small.tar.gz && psql < thai.sql

psql -d thai

\dt+ book.*

sudo mkdir /home/1 && sudo chmod 777 /home/1

sudo -u postgres psql

-- создадим табличку для тестов
CREATE DATABASE backup;
\c backup
SELECT current_database();
CREATE TABLE test (i int, col text);
INSERT INTO test VALUES (1, '123');
INSERT INTO test VALUES (2, '456');
INSERT INTO test VALUES (3, '789');

--скопируем данные
COPY test TO '/home/1/test.csv' CSV HEADER;

\! cat /home/1/test.csv

-- восстановим данные в другую табличку
-- ошибка!!!
COPY test2 FROM '/home/1/test.csv' CSV HEADER;

-- таблица должна быть создана заранее
CREATE TABLE test2 (i int, col text);
COPY test2 FROM '/home/1/test.csv' CSV HEADER;
SELECT * FROM test2;

-- архивируем БД через консольную утилиту
\! pg_dump -d backup --create
\! pg_dump -d backup --create > /home/1/1.sql
\! cat /home/1/1.sql

-- заархивировать
\! pg_dump -d backup --create | gzip > /home/1/backup.gz
\! cat /home/1/backup.gz

-- для pg_restore - кастомный сжатый формат
\! pg_dump -d backup -Fc > /home/1/custom.gz

-- посмотрим содержимое через cat
\! clear
\! cat /home/1/custom.gz

-- восстановим БД
\! psql < /home/1/1.sql
\dt
TABLE test;

-- через pgrestore
DROP DATABASE IF EXISTS backup;
\c postgres
CREATE DATABASE backup;
\! pg_restore /home/1/custom.gz -d backup

-- кастомное восстановление 
DROP DATABASE IF EXISTS backup;
CREATE DATABASE backup;
\! pg_restore /home/1/custom.gz -d backup -t test2
\c backup
\dt
TABLE test2;


-- если перекодировать 
pg_dump ... | iconv -f utf-8 -t cp-1251 > dump.sql


-- посмотрим на параметры pg_dump && pg_restore
\! pg_dump --help
\! pg_restore --help

-- pg_dumpall
\! pg_dumpall > /home/1/backup.sql
\! ls -la /home/1/
\! cat /home/1/backup.sql | grep thai
\! pg_dumpall --clean --globals-only > /home/1/globals.sql
\! cat /home/1/globals.sql
\! pg_dumpall --clean --schema-only > /home/1/schema.sql
\! cat /home/1/schema.sql

-- Восстановление
\! psql < /home/1/backup.sql


-- pg_probackup
-- Создание и восстановление резервной копии с помощью pg_probackup
-- лицензия
-- https://github.com/postgrespro/pg_probackup/blob/master/LICENSE
pg_lsclusters

-- Add the pg_probackup repository GPG key

sudo apt install gpg wget -y && wget -qO - https://repo.postgrespro.ru/pg_probackup/keys/GPG-KEY-PG-PROBACKUP | sudo tee /etc/apt/trusted.gpg.d/pg_probackup.asc

-- Setup the binary package repository
. /etc/os-release
echo "deb [arch=amd64] https://repo.postgrespro.ru/pg_probackup/deb $VERSION_CODENAME main-$VERSION_CODENAME" | \
sudo tee /etc/apt/sources.list.d/pg_probackup.list
-- Optionally setup the source package repository for rebuilding the binaries

echo "deb-src [arch=amd64] https://repo.postgrespro.ru/pg_probackup/deb $VERSION_CODENAME main-$VERSION_CODENAME" | \
sudo tee -a /etc/apt/sources.list.d/pg_probackup.list
-- List the available pg_probackup packages

-- Using apt:

sudo apt update -y
apt search pg_probackup


-- если в списке нет вашей новейшей ОС можно:
/*
cd /etc/apt/sources.list.d
sudo nano pg_probackup.list
hirsute -> focal
main-hirsute -> focal
sudo apt update
*/

-- 18 поставим доп пакеты
sudo DEBIAN_FRONTEND=noninteractive apt install pg-probackup-18 pg-probackup-18-dbg postgresql-contrib -y

-- Создаем каталог и устанавливаем переменную окружения BACKUP_PATH
-- в проде так делать НЕ НАДО!!!!
sudo rm -rf /home/backups2 && sudo mkdir /home/backups2 && sudo chmod 777 /home/backups2

-- всё под пользователем postgres
sudo su postgres

echo "BACKUP_PATH=/home/backups2/">>~/.bashrc
echo "export BACKUP_PATH">>~/.bashrc
cd
. .bashrc

echo $BACKUP_PATH

-- Создадим роль в PostgreSQL для выполнения бекапов и дадим ему соответствующие права
-- права нужно будет выдавать в каждой БД!!!
-- https://postgrespro.github.io/pg_probackup/#pbk-install-and-setup
psql

/* -- для 14- версий
    create user backup;
    ALTER ROLE backup NOSUPERUSER;
    ALTER ROLE backup WITH REPLICATION;
    GRANT USAGE ON SCHEMA pg_catalog TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.pg_start_backup(text, boolean, boolean) TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.pg_stop_backup(boolean, boolean) TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.pg_create_restore_point(text) TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.pg_switch_wal() TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.pg_last_wal_replay_lsn() TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.txid_current() TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.txid_current_snapshot() TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.txid_snapshot_xmax(txid_snapshot) TO backup;
    GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_checkpoint() TO backup;

-- в 15+ версии другой скрипт %)
    REVOKE ALL PRIVILEGES ON FUNCTION current_setting(text) FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION pg_switch_wal() FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION txid_current() FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION txid_current_snapshot() FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION txid_snapshot_xmax(txid_snapshot) FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION pg_create_restore_point(text) FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION pg_control_checkpoint() FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION pg_is_in_recovery() FROM backup;
    REVOKE ALL PRIVILEGES ON FUNCTION pg_last_wal_replay_lsn() FROM backup;
    REVOKE ALL PRIVILEGES ON SCHEMA pg_catalog FROM backup;
    DROP USER backup;
*/

-- в 15+ версии

BEGIN;
CREATE ROLE backup WITH LOGIN;
GRANT USAGE ON SCHEMA pg_catalog TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_start(text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_stop(boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_create_restore_point(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_switch_wal() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_last_wal_replay_lsn() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current_snapshot() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_snapshot_xmax(txid_snapshot) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_checkpoint() TO backup;
COMMIT;

ALTER ROLE backup WITH REPLICATION;

exit

-- !!! если снимаем бэкап по сети - pg_hba
cat /etc/postgresql/18/main/pg_hba.conf

-- Инициализируем наш бекап (однократная процедура - создает структуру каталогов)
ls -l /home/backups2
pg_probackup-18 init

-- отключить
-- sudo rm -rf /home/backups2 && sudo mkdir /home/backups2 && sudo chmod 777 /home/backups2

-- В нашей директории для бекапов появились следующие папки
ls -l $BACKUP_PATH

-- Инициализируем инстанс main
pg_probackup-18 add-instance --instance 'main' -D /var/lib/postgresql/18/main

-- Создадим резервную копию.  Команда backup принимает три параметра:
    - `-b` - тип создания резервной копии. Для первого запуска нужно создать полную копию кластера PostgreSQL, поэтому команда `FULL`
    - параметр `-–stream` указывает на то, что нужно вместе с созданием резервной копии, параллельно передавать wal по слоту репликации. Запуск потоковой передачи wal.
    - параметр `--temp-slot` указывает на то, что потоковая передача wal-ов будет использовать временный слот репликации


-- посмотреть настройки
pg_probackup-18 show-config --instance main

pg_probackup-18 backup --instance 'main' -b FULL --stream --temp-slot

-- ERROR: could not connect to database postgres: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: 
-- FATAL:  number of requested standby connections exceeds "max_wal_senders" (currently 0)
nano /etc/postgresql/18/main/postgresql.conf

pg_ctlcluster 18 main reload

pg_probackup-18 backup --instance 'main' -b FULL --stream --temp-slot

pg_ctlcluster 18 main stop && pg_ctlcluster 18 main start

-- Видим, что наш бекап успешно создался. Однако есть предупреждение
-- WARNING: Current PostgreSQL role is superuser. It is not recommended to run pg_probackup under superuser.

-- поменяем пароль backup
psql -c "ALTER USER backup PASSWORD 'thai2123';"

-- rm ~/.pgpass
echo "localhost:5432:*:backup:thai2123">>~/.pgpass
chmod 600 ~/.pgpass

pg_probackup-18 backup --instance 'main' -b FULL --stream --temp-slot -h localhost -U backup

WARNING: Could not read WAL record at 0/217E85E8: invalid record length at 0/217E85E8: expected at least 24, got 0
INFO: Wait for LSN 0/217E85E8 in streamed WAL segment /home/backups2/backups/main/TIOHZB/database/pg_wal/000000010000000000000021
WARNING: Could not read WAL record at 0/217E85E8: invalid record length at 0/217E85E8: expected at least 24, got 0
WARNING: Could not read WAL record at 0/217E85E8: invalid record length at 0/217E85E8: expected at least 24, got 0

-- !!! ожидает конца WAL файла
-- gcloud compute ssh postgres
-- sudo -u postgres psql
psql 
checkpoint;


pg_probackup-18 backup --instance 'main' -b DELTA --stream --temp-slot -h localhost -U backup


-- Если не включена контрольная сумма (в 18+ она включена по умолчанию), то желательно её включить
-- изменить можно только на выключенном кластере
/*
    pg_ctlcluster 18 main stop
    /usr/lib/postgresql/18/bin/pg_checksums -D /var/lib/postgresql/18/main --enable
    pg_ctlcluster 18 main start
*/

pg_lsclusters


pg_probackup-18 show

-- Давайте теперь в нашу таблицу test внесем дополнительные данные
psql -c 'create table test(i int);insert into test values (4);'

-- создам PAGE бэкап
pg_probackup-18 backup --instance 'main' -b PAGE --stream --temp-slot -h localhost -U backup

-- INFO: Wait for WAL segment /home/backups2/wal/main/000000010000000000000021 to be archived

SELECT pg_switch_wal();

-- не помогло...
-- неправильно настроена автоматическая архивация WAL
-- настроим непрерывное архивирование
-- https://postgrespro.ru/docs/postgrespro/13/app-pgprobackup#PBK-SETTING-UP-CONTINUOUS-WAL-ARCHIVING
-- https://habr.com/ru/company/barsgroup/blog/516088/
psql -c 'alter system set archive_mode = on'

-- вручную каталог(
psql -c 'show archive_mode;'
psql -c 'show archive_command;'

psql -c "alter system set archive_command = 'pg_probackup-18 archive-push -B /home/backups2/ --instance=main --wal-file-path=%p --wal-file-name=%f --compress';"

-- !!! всё бы хорошо, НО !!!
-- на проде никто не делает локальные бэкапы

pg_ctlcluster 18 main stop && pg_ctlcluster 18 main start

ls -la /home/backups2/wal/main

pg_probackup-18 backup --instance 'main' -b PAGE --stream --temp-slot -h localhost -U backup
-- ERROR: Thread [1]: WAL segment "/home/backups2/wal/main/000000010000000000000021" is absent

pg_probackup-18 backup --instance 'main' -b FULL --stream --temp-slot -h localhost -U backup
pg_probackup-18 backup --instance 'main' -b PAGE --stream --temp-slot -h localhost -U backup
pg_probackup-18 show


-- если нужно сжатие
-- [--compress-algorithm=алгоритм_сжатия] [--compress-level=уровень_сжатия]
-- https://postgrespro.ru/docs/postgrespro/18/app-pgprobackup#PBK-OPTIONS

-- Если что-то пошло не так, то можно удалить привязку инстанса:
-- pg_probackup-18 del-instance --instance 'main'



-- восстановим нашу копию ???
-- создадим новый кластер

pg_createcluster 18 main2
rm -rf /var/lib/postgresql/18/main2

pg_probackup-18 restore --instance 'main' -i 'TLGVJ4' -D /var/lib/postgresql/18/main2 
-- если не задали переменную окружения
-- -B /home/backups


pg_ctlcluster 18 main2 start

-- Проверяем, что данные восстановились
psql -p 5433 -c 'select * from test;'



-- дифференциальные бэкапы
-- PTRACK
-- https://github.com/postgrespro/ptrack
-- как видим далеко не всё так просто

-- политика хранения резервных копии
pg_probackup-18 show

-- хранение одной полной копии базы данных
-- pg_probackup-18 set-config --instance  'main' --retention-redundancy=1

-- pg_probackup-18 delete --instance  'main' --delete-expired --delete-wal
-- pg_probackup-18 show

-- старше 7 дней и не больше 2 полных копий
-- pg_probackup-18 delete --instance 'main' --delete-expired --retention-window=7 --retention-redundancy=2

-- сколько дней хранить wal
-- pg_probackup set-config --instance db1 --wal-depth=3


-- настройки и скрипт бэкапа
-- посмотреть настройки
pg_probackup-18 show-config --instance main
-- https://habr.com/ru/company/barsgroup/blog/515592/


-- PITR
-- https://postgrespro.ru/docs/postgrespro/18/app-pgprobackup#PBK-PERFORMING-POINT-IN-TIME-PITR-RECOVERY

psql -c "insert into test values (5);"

pg_probackup-18 backup --instance 'main' -b PAGE --stream --temp-slot -h localhost -U backup

pg_ctlcluster 18 main2 stop

rm -rf /var/lib/postgresql/18/main2

pg_probackup-18 show
date
pg_probackup-18 restore --instance 'main' -i 'TLGVJ4' -D /var/lib/postgresql/18/main2 -B /home/backups2 --recovery-target-time="2026-09-16 17:09:50+00"

pg_ctlcluster 18 main2 start

2026-09-13 10:17:15.772 UTC [13557] LOG:  database system is ready to accept read-only connections
INFO: pg_probackup archive-get WAL file: 000000010000000000000033, remote: none, threads: 1/1, batch: 1
ERROR: pg_probackup archive-get failed to deliver WAL file: 000000010000000000000033, time elapsed: 0ms
2026-09-13 10:17:15.781 UTC [13563] LOG:  redo done at 0/320000B8 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.41 s
2026-09-13 10:17:15.781 UTC [13563] LOG:  last completed transaction was at log time 2026-09-13 10:14:46.846935+00
2026-09-13 10:17:15.781 UTC [13563] FATAL:  recovery ended before configured recovery target was reached


ls -la /home/backups2/wal/main
-- нет ещё 33 файла

-- 1
-- Чтобы Postgres накатил всё, что у него есть, а при физическом отсутствии следующих WAL-файлов не падал в FATAL, а просто открывался, 
-- postgresql.conf параметр:inirecovery_target_incomplete_action = 'promote'

-- 2
psql
SELECT pg_switch_wal();
\! ls -la /home/backups2/wal/main

rm -rf /var/lib/postgresql/18/main2
pg_probackup-18 restore --instance 'main' -i 'TLASE5' -D /var/lib/postgresql/18/main2 -B /home/backups2 --recovery-target-time="2026-09-13 10:14:40+00"
pg_ctlcluster 18 main2 start

-- на самом деле
-- отсутствуют просто новые нужные закончившие транзакции)
-- 2026-09-13 10:21:45.172 UTC [13672] LOG:  last completed transaction was at log time 2026-09-13 10:14:46.846935+00

psql -p 5433 -c "table test;"

-- если запустилис в readonly SELECT pg_promote();

-- !!!! restore-as-replica
-- pg_probackup-18 restore --instance 'main' -D /var/lib/postgresql/18/main2 -B /home/backups --restore-as-replica

-- Проверяем, что данные восстановились без последних изменений


-- подключение через ssh
$PROBACKUP_BIN backup \
--instance="${CLUSTER_NAME_PREFIX}-${MASTER_HOST}" \
--threads=${THREADS_NUM} \
--backup-mode=${BACKUP_MODE} \
--remote-host="${MASTER_HOST}" \
--remote-port=${REMOTE_PORT} \
--remote-user=${REMOTE_USER} \
--ssh-options="-o StrictHostKeyChecking=no" \
--backup-path=${BACKUP_PATH} \
--pgdatabase=${REMOTE_PG_DATABASE} \
--pguser=${REMOTE_PG_USER} \
--pgport=${REMOTE_PG_PORT} \
--delete-expired \
--progress \
--compress \
--stream

-- восстановить конкретную БД
pg_probackup-18 restore  --instance='main' --db-include='backup' -D /var/lib/postgresql/18/main2

psql -p 5433 -d backup

gcloud compute instances delete postgres


