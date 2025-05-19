-- https://aristov.tech
-- Postgres operator GKE - уменьшаем мощность машины и указываем только 1 зону 1 региона

-- need to update in time
-- --cluster-version "1.25.7-gke.1000" (05/04/23)
-- --cluster-version "1.31.6-gke.1020000" (23/03/25)
-- 1.31.6-gke.1020000 (13.05) - не работает
gcloud beta container --project "celtic-house-266612" clusters create "postgresoperator" --zone "us-central1-c" --no-enable-basic-auth --cluster-version "1.32.2-gke.1297002" --release-channel "regular" --machine-type "e2-medium" --image-type "COS_CONTAINERD" --disk-type "pd-standard" --disk-size "30" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --max-pods-per-node "110" --preemptible --num-nodes "3" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/celtic-house-266612/global/networks/default" --subnetwork "projects/celtic-house-266612/regions/us-central1/subnetworks/default" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --enable-shielded-nodes --node-locations "us-central1-c"


gcloud container clusters list
-- https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
kubectl get all
-- если делать через веб интерфейс ошибка, нужно переинициализировать кластер
-- так как мы делали кластер не через gcloud, доступ мы не получим
-- нужно прописать теперь контекст
-- https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl
gcloud container clusters get-credentials postgresoperator --zone us-central1-c

kubectl get all

-- postgres operator
-- посмотрим существующие уже ресурсы
kubectl api-resources
cd /mnt/d/download

git clone https://github.com/zalando/postgres-operator
cd postgres-operator
-- https://helm.sh/docs/intro/install/
helm install postgres-operator ./charts/postgres-operator

-- убедимся, что postgres-operator стартовал:
kubectl --namespace=default get pods -l "app.kubernetes.io/name=postgres-operator"

-- посмотрим, что ресурс постгрес появился
kubectl api-resources | grep postgres

-- поставим UI к постгрес оператору
helm install postgres-operator-ui ./charts/postgres-operator-ui

-- To verify that postgres-operator has started, run:
kubectl --namespace=default get pods -l "app.kubernetes.io/name=postgres-operator-ui"

kubectl get all
kubectl port-forward svc/postgres-operator-ui 8081:80

-- http://localhost:8081/#new

-- создадим кластер через UI - на самом деле формирует ямл
name - minimal
instances - 2
-- галочку на pg_bouncer не ставим - не хватит ресурсов

-- посмотрим как развернулся
kubectl get all -A
kubectl get all -o wide

-- подробная информация о ноде
kubectl get node gke-postgresoperator-default-pool-9cc4eb0f-57mq -o wide
gcloud compute disks list

-- сколько задействовано ресурсов
kubectl top node gke-postgresoperator-default-pool-9cc4eb0f-57mq


-- Retrieve the password FROM the K8s Secret that is created in your cluster. 
-- Non-encrypted connections are rejected by default, so set the SSL mode to require:
export PGPASSWORD=$(kubectl get secret postgres.minimal.credentials.postgresql.acid.zalan.do -o 'jsonpath={.data.password}' | base64 -d)
echo $PGPASSWORD

-- такой вариант или генерировать сертификаты и прокидывать доступ
-- XhWXAQTxnq8I3jN21mqf331LGq0efza4UhnOSwsjHV82KqGBCxqDtLCCst7EiTPA

kubectl port-forward pod/minimal-repl 5433:5432
kubectl port-forward service/minimal-repl 5433:5432

psql -U postgres -h localhost -p 5433 sslmode=disable -W
psql -U postgres -h localhost -p 5433 -W


-- ssl теперь включено по умолчанию
-- https://www.postgresql.org/docs/current/libpq-ssl.html
kubectl exec -it pod/minimal-0 -- bash
cd /home/postgres/pgdata/pgroot/data
cat postgresql.conf
cat pg_hba.conf
psql -U postgres

kubectl exec -it pod/minimal-1 -- patronictl -c postgres.yml list


gcloud container clusters list
gcloud container clusters delete postgresoperator --zone us-central1-c

--посмотрим, что осталось от кластера
gcloud compute disks list


