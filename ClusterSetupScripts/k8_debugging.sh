# Deploy DNS util pod
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
kubectl get pods dnsutils
kubectl exec -i -t dnsutils -- nslookup kubernetes.default
kubectl exec -i -t dnsutils -- nslookup router.vt

# Get Kube DNS logs
kubectl logs --namespace=kube-system -l k8s-app=kube-dns

# Reset Kube DNS service
kubectl delete pod -l k8s-app=kube-dns -n kube-system


# Get configmap and pipe to local yaml
kubectl get configmap cilium-config -n kube-system -o yaml > cilium-config.yaml

# Get Cilium service list
kubectl -n kube-system exec -it $(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium service list

# Reset Cilium
kubectl -n kube-system rollout restart ds/cilium