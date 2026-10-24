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
./verify-tunnel.sh --ngrok-host <name>.ngrok-free.dev   # also check the ngrok address, while both run
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

## Moving from ngrok: the runbook

ngrok keeps running until the very end, so the portal stays up throughout and every phase can be undone. Do the phases in
order, and don't start one until the previous one's check passes. `<domain>` is your Wix domain and `portal.<domain>` the
portal's new address (any subdomain works; the website on the root domain and `www` is not touched).

### Phase 0 (ahead of time): ask Bouncr to allow the new origin
Ask Bouncr to allow `https://portal.<domain>` as an origin for the venue, **in addition to** the ngrok address. Until they do,
the Applicant Page fails with `UNAUTHORIZED (19)` (visible with `?debug=1`). Only phase 5 needs it, but you can't control how
long it takes. Phases 1–4 can go ahead meanwhile.

### Phase 1: copy the Wix DNS into Cloudflare (nothing changes yet)
1. Sign up at https://dash.cloudflare.com (the Free plan is enough), **Add a domain**, enter `<domain>`, and pick **Free**.
2. Cloudflare scans the existing records. In another tab, open Wix: **Domains** → the `⋯` (Domain Actions) next to the domain →
   **Manage DNS Records**. (Labels differ a little between Wix's dashboard versions.)
3. Go through Wix's list **row by row** and make sure Cloudflare has the same record (type, name, value, priority for MX).
   The scan often misses some: look especially at **MX**, **TXT** (SPF `v=spf1…`, DMARC on `_dmarc`, Google/Microsoft
   verification) and **CNAME**s for DKIM (`…._domainkey`). Add anything missing by hand.
4. Set the records for the Wix website, the root `A` record(s) and the `www` CNAME (e.g. to `cdn1.wixdns.net`), to **DNS only**
   (grey cloud). Wix serves its own certificate, and Cloudflare's proxy in front of it causes certificate and redirect errors.
   Set the mail-related records to DNS only too (Cloudflare does that for MX by itself).
5. If Wix shows DNSSEC as on for the domain, turn it off there and wait 24 hours before phase 2. Otherwise resolvers that
   validate DNSSEC will reject the domain during the change.

*Check:* every row in Wix's list is in Cloudflare. *Undo:* nothing has changed; delete the site from Cloudflare if you want.

### Phase 2: point the domain at Cloudflare's nameservers
1. Cloudflare's **Overview** for the domain shows two nameservers (`<name>.ns.cloudflare.com`).
2. In Wix: **Domains** → `⋯` → **Advanced** → **Change Name Servers** (on some dashboards: **Manage DNS Records** → **Edit name
   servers**, or "Point to another provider"). Choose custom nameservers and enter Cloudflare's two in place of Wix's.
   Write down Wix's original nameservers first, for undo.
3. Wait for Cloudflare to mark the domain **Active** (it emails you). Usually under an hour, at most 24 hours. Cloudflare's
   **Check nameservers now** button speeds up the check.
4. In Cloudflare: **SSL/TLS** → **Edge Certificates**: turn on **Always Use HTTPS**. Optionally turn on DNSSEC in Cloudflare
   (**DNS** → **Settings**) and add the DS record it gives at Wix, if Wix offers that.

*Check:* `dig +short NS <domain>` shows Cloudflare's two; the Wix site loads at `https://<domain>` and `https://www.<domain>`;
an email sent to an address on the domain arrives. *Undo:* put Wix's nameservers back. The cluster hasn't changed.

### Phase 3: start the tunnel next to ngrok
On your laptop (`cloudflared` from https://github.com/cloudflare/cloudflared/releases, any recent version):
```
cloudflared tunnel login                 # browser: pick <domain>; writes ~/.cloudflared/cert.pem (keep it on the laptop)
cloudflared tunnel create home           # writes ~/.cloudflared/<tunnel-id>.json: the tunnel's credentials
```
1. Add `CLOUDFLARE_TUNNEL_CREDENTIALS=~/.cloudflared/<tunnel-id>.json` to `../.env`.
2. Replace `portal.example.com` with `portal.<domain>` in `tunnel-config.yaml` **and** in
   `../GlooGateway/routes/external-routes.yaml` (where it sits next to the ngrok domain), then
   `kubectl apply -f ../GlooGateway/routes/external-routes.yaml`.
3. `./install-cloudflared.sh`
4. `cloudflared tunnel route dns home portal.<domain>`. This makes the proxied CNAME `portal` → `<tunnel-id>.cfargotunnel.com`.
5. `./verify-tunnel.sh --ngrok-host ezequiel-thirstless-johnnie.ngrok-free.dev`

*Check:* `verify-tunnel.sh` passes, with both addresses serving the portal. Nothing the portal sends out has changed yet: links
still use the ngrok address. *Undo:* remove the hostname from `external-routes.yaml` and apply it,
`kubectl delete namespace cloudflared`, and delete the `portal` record in Cloudflare.

### Phase 4: get the caller address right
If `verify-tunnel.sh` failed on `TRUST_PROXY`, change the portal chart's `trustProxy` to the value it names, deploy that
first (with the ngrok address still as `DEPLOY_PUBLIC_URL`), and run `verify-tunnel.sh` again.

Then check it by hand: on a phone using mobile data (not your Wi-Fi), open `https://portal.<domain>/admin` and get the password
wrong until it says "Too many sign-in attempts". Your laptop on Wi-Fi must still be able to sign in, which shows the attempts
are counted per caller.

### Phase 5: switch the portal to the new address
Once Bouncr allows the new origin, in the `id-verification-portal` repository:
1. Set `DEPLOY_PUBLIC_URL=https://portal.<domain>` in its `.env`.
2. `npm run deploy -- --dry-run`, then `npm run deploy`.
3. Sign in at `https://portal.<domain>/admin`. Everyone signs in again once: sign-in cookies belong to one address.
4. Run `docs/smoke-checklist.md` on a phone with a Test ID, including a Lease's signing step.

*Check:* new Verification Links start with `https://portal.<domain>/v/`, and the smoke checklist passes. *Undo:* put the ngrok
address back in `DEPLOY_PUBLIC_URL` and `npm run deploy` (or `helm rollback`). Links made in between keep working, because the
tunnel stays up.

### Phase 6: let the ngrok links run out
A Verification Link contains its full address, so links sent before phase 5 only work while ngrok is up. Leave ngrok running
for `LINK_TTL_DAYS` after phase 5 (7 by default, see the portal's README). *Check:* no Applicant on the Admin Page was given a
link before phase 5 that is still unexpired and unfinished.

### Phase 7: remove ngrok
In this order, so nothing is left behind on a finalizer:
1. `kubectl delete -f ../GlooGateway/external-ngrok-ingress.yaml` and `kubectl delete -f ../TestDeployment/nginx-tunnel.yaml`.
   Wait until `kubectl get ingress -A` shows neither (the operator removes their finalizers).
2. Remove the ngrok domain from `../GlooGateway/routes/external-routes.yaml` and apply it.
3. `helm uninstall ngrok-operator --namespace ngrok-operator`
4. `kubectl get crd -o name | grep ngrok` and delete what's listed; then `kubectl delete namespace ngrok-operator`.
5. In ngrok's dashboard, release the `*.ngrok-free.dev` domain. Remove `NGROK_API_KEY` and `NGROK_AUTHTOKEN` from `../.env`.
6. Ask Bouncr to drop the ngrok origin.
7. In git: delete `../NgrokTunnel/`, `../GlooGateway/external-ngrok-ingress.yaml` and `../TestDeployment/nginx-tunnel.yaml`.

*Check:* `./verify-tunnel.sh` (no `--ngrok-host`) passes, and `kubectl get ingressclass,crd | grep -i ngrok` prints nothing.
*Undo:* `../NgrokTunnel/install-ngrok.sh` and re-apply the Ingress from git history.
