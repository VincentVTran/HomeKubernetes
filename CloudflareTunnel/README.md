### Documentation
https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ (Cloudflare Tunnel) and
https://developers.cloudflare.com/dns/zone-setups/full-setup/ (moving a domain's DNS to Cloudflare).

### What runs here (namespace `cloudflared`)
`cloudflared` (image `cloudflare/cloudflared:2026.10.0`, 2 replicas) makes outbound connections to Cloudflare and carries the
public hostnames in `tunnel-config.yaml` to Gloo's **external** gateway (`external-gateway-proxy.gloo-system:80`), which serves
only `exposure: external` VirtualServices. No port is opened on the home network, and the internal gateway (Grafana,
Prometheus, `/logs`) stays LAN-only. HTTPS ends at Cloudflare with its own certificate for the hostname.

```
Internet ──https──> Cloudflare edge ──tunnel──> cloudflared pods ──http──> external-gateway-proxy ──> external-vs ──> portal
```

| File | What it is |
|---|---|
| `tunnel-config.yaml` | cloudflared's config: hostname → service rules, catch-all 404. Goes into the ConfigMap `cloudflared-config` |
| `cloudflared.yaml` | Namespace and Deployment (probes on `/ready`, metrics on `:2000` scraped by Prometheus, non-root, read-only) |
| `install-cloudflared.sh` | First install: makes the Secret `cloudflared-tunnel` from the credentials file in `../.env`, then upgrades |
| `upgrade-cloudflared.sh` | Applies the config and Deployment; refuses a placeholder hostname or one missing from the external routes |
| `verify-tunnel.sh` | Checks the public path end to end, from outside (below) |

- The tunnel is **locally managed**: its routing lives here in git, not in Cloudflare's dashboard. The tunnel id and secret come
  from the file `cloudflared tunnel create` wrote, named by `CLOUDFLARE_TUNNEL_CREDENTIALS` in `../.env`. They never go into git
  or onto a command line.
- A change to `tunnel-config.yaml` takes effect with `./upgrade-cloudflared.sh`, which restarts the pods one at a time.
- Memory: 64Mi request and 256Mi limit per pod, so 512Mi at the limits for both.
- Prometheus metrics: `cloudflared_tunnel_ha_connections` (4 per pod: a named tunnel's default), `cloudflared_tunnel_total_requests` and
  `cloudflared_tunnel_request_errors`.

### Adding a public hostname
1. Add a rule to `tunnel-config.yaml` above the catch-all, pointing at the external gateway as the existing one does.
2. Add the hostname to an `exposure: external` VirtualService's `domains` (`../GlooGateway/routes/`), then `kubectl apply` it.
3. `./upgrade-cloudflared.sh`, then `cloudflared tunnel route dns home <hostname>`.

### Checking it: `verify-tunnel.sh`
```
./verify-tunnel.sh                                   # the first hostname in tunnel-config.yaml
./verify-tunnel.sh --skip-caller-address             # read-only: don't add the temporary route
```
It checks that every cloudflared pod is connected, that `https://<host>/api/health` answers `{"ok":true}` through Cloudflare
with a valid certificate, that `/admin` serves the web app, that unknown hostnames and the internal paths (`/grafana`,
`/prometheus`, `/logs`) never reach anything, and which `X-Forwarded-For` chain the portal gets. From that chain it says which
`TRUST_PROXY` (the portal chart's `trustProxy`) picks out the caller, and fails if the portal runs with another value, because
then failed sign-ins would be counted against the wrong address. It also sends a forged `X-Forwarded-For` and fails if that changes the
address the portal picks. For this last check it adds a route on a random path of `external-vs` to a `whoami` pod in a
throwaway namespace for a few seconds, and removes both when it exits, also on Ctrl-C.

If a run was killed outright (`kill -9`, a closed laptop), that route can be left behind, publicly echoing request headers.
Find and remove it:
```
kubectl get virtualservice external-vs -n gloo-system -o jsonpath='{range .spec.virtualHost.routes[*]}{.matchers[0].exact}{"\n"}{end}'
kubectl edit virtualservice external-vs -n gloo-system    # delete the route whose matcher is exact: /__verify-tunnel-<random>
kubectl get namespaces -o name | grep verify-tunnel- | xargs -r kubectl delete
```
`kubectl apply -f ../GlooGateway/routes/external-routes.yaml` also puts the routes back as they are in git.
Tested against Gloo 1.22.7 with default settings: Gloo passes Cloudflare's `X-Forwarded-For` (just the caller) through
unchanged, so `trustProxy: 1` is right.

---

## Setting it up from scratch
For a rebuilt cluster or a new tunnel. The domain is `vtranlabs.com`, registered with Cloudflare Registrar (2026-10-24), so
its DNS is on Cloudflare already. The portal is at `rental.vtranlabs.com`; other apps get their own subdomains.

1. In Cloudflare's dashboard, check once: **Domain Registration** → **Manage domain** has **Auto Renew** on (every app's
   address depends on the domain), and **SSL/TLS** → **Edge Certificates** has **Always Use HTTPS** on.
2. On your laptop (`cloudflared` from https://github.com/cloudflare/cloudflared/releases, any recent version):
   ```
   cloudflared tunnel login                 # browser: pick vtranlabs.com; writes ~/.cloudflared/cert.pem (keep it on the laptop)
   cloudflared tunnel create home           # writes ~/.cloudflared/<tunnel-id>.json: the tunnel's credentials
   ```
3. Add `CLOUDFLARE_TUNNEL_CREDENTIALS=~/.cloudflared/<tunnel-id>.json` to `../.env`.
4. `kubectl apply -f ../GlooGateway/routes/external-routes.yaml`, then `./install-cloudflared.sh`.
5. `cloudflared tunnel route dns home rental.vtranlabs.com`. This makes the proxied CNAME `rental` → `<tunnel-id>.cfargotunnel.com`.
6. `./verify-tunnel.sh`. If it fails on `TRUST_PROXY`, set the portal chart's `trustProxy` to the value it names and deploy.
7. Bouncr must allow `https://rental.vtranlabs.com` as an origin for the venue, or the Applicant Page fails with
   `UNAUTHORIZED (19)` (visible with `?debug=1`).
8. In the `id-verification-portal` repository, `DEPLOY_PUBLIC_URL=https://rental.vtranlabs.com` in its `.env`, then
   `npm run deploy`, and run its `docs/smoke-checklist.md` on a phone.

## History: ngrok
Until 2026-10-24 the portal was public through ngrok (`ezequiel-thirstless-johnnie.ngrok-free.dev`, the ngrok operator and
an Ingress to the external gateway). It was removed in one go with nothing using it: the portal was switched to
`rental.vtranlabs.com`, then the Ingress, the operator, its CRDs and namespace were deleted, along with `NgrokTunnel/`,
`GlooGateway/external-ngrok-ingress.yaml` and `TestDeployment/nginx-tunnel.yaml`. Verification Links made before then use
the ngrok address and no longer open. The files are in git history, before the commit that removed them.
