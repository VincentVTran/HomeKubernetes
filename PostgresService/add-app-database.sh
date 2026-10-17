#!/bin/bash
# Gives one app its own database and login on the shared Postgres, and puts its connection URL in a Secret in the app's namespace
# (pods cannot read Secrets from other namespaces). Safe to run again: an existing password is kept.
#   ./add-app-database.sh <app> <app-namespace>
# The app then reads the key `uri` of Secret `<app>-db` in its namespace, for example:
#   helm install ... --set database.existingSecret=<app>-db
set -euo pipefail
APP=${1:?usage: add-app-database.sh <app> <app-namespace>}
APP_NAMESPACE=${2:?usage: add-app-database.sh <app> <app-namespace>}
DB=${APP//-/_}                 # Postgres names: underscores instead of dashes
CLUSTER=shared-postgres
NAMESPACE=postgres
HOST="$CLUSTER-rw.$NAMESPACE.svc.cluster.local"

# Reuse the password if the login already exists, otherwise make one.
if kubectl get secret "$APP-db-login" --namespace "$NAMESPACE" >/dev/null 2>&1; then
  PASSWORD=$(kubectl get secret "$APP-db-login" --namespace "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
else
  PASSWORD=$(openssl rand -hex 24)
fi

# The login: a basic-auth Secret that CloudNativePG reads, reloading the role when it changes.
kubectl apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: $APP-db-login
  namespace: $NAMESPACE
  labels: { cnpg.io/reload: "true" }
type: kubernetes.io/basic-auth
stringData: { username: $DB, password: $PASSWORD }
YAML

# The role, added to the live Cluster once (cluster.yaml leaves managed.roles out, so `kubectl apply` keeps it).
ROLE="{\"name\":\"$DB\",\"login\":true,\"passwordSecret\":{\"name\":\"$APP-db-login\"}}"
ROLES=$(kubectl get cluster "$CLUSTER" --namespace "$NAMESPACE" -o jsonpath='{.spec.managed.roles[*].name}')
if [[ -z "$ROLES" ]]; then
  kubectl patch cluster "$CLUSTER" --namespace "$NAMESPACE" --type=merge -p "{\"spec\":{\"managed\":{\"roles\":[$ROLE]}}}"
elif ! tr ' ' '\n' <<<"$ROLES" | grep -qx "$DB"; then
  kubectl patch cluster "$CLUSTER" --namespace "$NAMESPACE" --type=json -p "[{\"op\":\"add\",\"path\":\"/spec/managed/roles/-\",\"value\":$ROLE}]"
fi

# The database, owned by that role.
kubectl apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: $APP
  namespace: $NAMESPACE
spec:
  cluster: { name: $CLUSTER }
  name: $DB
  owner: $DB
YAML

# The connection URL, where the app can read it.
kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic "$APP-db" --namespace "$APP_NAMESPACE" \
  --from-literal=uri="postgresql://$DB:$PASSWORD@$HOST:5432/$DB" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Database $DB is ready. $APP reads its URL from Secret $APP-db (key uri) in namespace $APP_NAMESPACE."
