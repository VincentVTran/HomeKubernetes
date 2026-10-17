### Documentation
https://cloudnative-pg.io/documentation/current/

### Install
Installs the CloudNativePG operator and one shared Postgres Cluster (`shared-postgres` in namespace `postgres`):
```
cd PostgresService && ./install-postgres.sh
```

### Add a database for an app
Each app gets its own database and login. Passwords are generated and never written to this repository:
```
./add-app-database.sh id-verification-portal id-verification-portal
```
The app reads its connection URL from the key `uri` of Secret `<app>-db` in its own namespace. That Secret is a copy (pods cannot read
Secrets in the `postgres` namespace), so to change an app's password: delete `<app>-db-login` in `postgres`, run the script again, and
restart the app.

The logins live only on the running Cluster, not in `cluster.yaml`, so `kubectl apply -f cluster.yaml` keeps them. If ArgoCD ever
manages this folder, add `ignoreDifferences` for `/spec/managed` on the Cluster, or it will remove every app's login.

### Connect with psql
```
kubectl exec -it shared-postgres-1 --namespace postgres -- psql
```
