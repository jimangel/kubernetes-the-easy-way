Source: https://dexidp.io/docs/getting-started/
Source: https://github.com/dexidp/helm-charts

### Pre-reqs

- Helm [installed](https://helm.sh/docs/intro/install/)
- [Ingress Controller](ingress-controller.md) deployed
- [cert-manager](certmanager.md) deployed

### UPDATE: March 27th 2023

Looking at some of the open issues / PRs (including ones that solve my needs), they date back to the beginning of this year with no activity from maintainers.

If you look at older versions of this file, you'll see I used to use gangway as the static client (which is now deprecated: https://github.com/vmware-archive/gangway)

TL;DR: I don't think Dex is actively maintained, or at the very least, the helm charts. Therefore, after this update, I plan on making no future changes.

### Why?

This allows us to authenticate to the Kubernetes API server using another identity provider. Using dex allows for multiple, plugable, identity backends.

I started using dex because it allowed me to add LDAP to Kubernetes, but for this demo I'll use GitHub as the AuthN of choice.

If you don't want to extend the Kubernetes API AuthN - but still want AuthN at the ingress, consider using something a bit more basic "on-top" like: https://github.com/oauth2-proxy/oauth2-proxy. It could be layered via ingress annotations. The key difference is authenticating to applications on the cluster or authenticating to the Kubernetes API server.

Using GitHub as the OIDC identity provider, means I can create Kubernetes RBAC (AuthZ) about GitHub OIDC claims. "Anyone" I grant access to, with a valid GitHub login and a correctly configured kubectl config could access my cluster. The key point is that it's only who: "I grant access to."

It's important to understand the flow:

> staticClient (kube-login or UI) -> dex (oidc) -> GitHub (oidc) -> dex (oidc) -> refreshed credentials (to API / staticClient)

While you could just use GitHub directly, you lose the ability to configure multiple oidc connectors.

### Setup an OAuth app in Github

GitHub > Settings > Developer Settings > OAuth Apps > Register a new application

![](img/register-new.png)

Settings:

![](img/app-settings.png)

Export clientID and Secret:

Click "Generate a new client secret" and use it in the following section.

```
export CLIENT_ID=<YOUR CLIENT ID>
export CLIENT_SECRET=<YOUR CLIENT SECRET>
```

### Setup Kubernetes API servers

Adding these flags, assuming no typos, should have no impact to the existing behavior of your API server. We're adding AuthN methods and not removing anything. It can be done before we actually have oidc setup completely.

We need to instruct the API server to support our OIDC source. Assuming you're using Let's Encrypt for the dex (OIDC) HTTPS endpoint, let's create the CA cert. We do this so the API server can leverage our OIDC configuration and "trust" LetsEncrypt as the issuing CA.

To update the API server, modify the static manifest (`/etc/kubernetes/manifests/kube-apiserver.yaml`) which kubelet automatically reads when changed. Note that any typo here could prevent the API server from starting and it might be worth backing up the file (or rebuilding).

```
# ssh into the control plane node
ssh -i ${TF_VAR_pub_key} kubernetes@$(terraform output -json control_plane_ip | jq -r '.[]')

# copy the letsencrypt cert stack to the node
curl https://letsencrypt.org/certs/isrgrootx1.pem.txt > isrgrootx1.pem.txt
curl https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt > lets-encrypt-x3-cross-signed.pem.txt
cat isrgrootx1.pem.txt lets-encrypt-x3-cross-signed.pem.txt > letsencrypt.pem

# move cert to kubernetes pki
cp letsencrypt.pem /etc/kubernetes/pki/letsencrypt.pem
```

This can be setup without impact to existing auth / access. The flags configure the Kubernetes API server for OIDC but since we don't use OIDC for AuthN - there is no impact.

```
# update the API server configuration
vi /etc/kubernetes/manifests/kube-apiserver.yaml

# insert / copy the following to the bottom of `spec.containers.command:`

# ENSURE TO UPDATE "YOURDOMAIN.COM" or you'll see it in the api server logs.

    - --oidc-ca-file=/etc/kubernetes/pki/letsencrypt.pem
    - --oidc-client-id=kubelogin-test
    - --oidc-groups-claim=groups
    - --oidc-issuer-url=https://dex2.YOURDOMAIN.COM
    - --oidc-username-claim=email

# confirm the API server is running (it should exist and have been recently restarted)
sudo crictl ps | grep api

# return to your local shell
exit
```

### Install Dex

For Dex, we're going to use our SSL passthrough on the LB so we can terminate SSL on the pod. It's been awhile since I've tested, but a few years ago, you could TCP dump credentials at the node level if using HTTP (behind a HTTPS LB). When the sslPassthrough annotation is passed to the ingress, it ignores any other rules / configurations and does a basic L4 passthrough.

Additionally, I create a staticClient redirectURI config for both kube-login and a test sample app.

>```
>    --set config.staticClients[0].redirectURIs[0]="http://localhost:8000" \
>    --set config.staticClients[0].redirectURIs[1]="http://localhost:18000" \
>    --set config.staticClients[0].redirectURIs[2]="http://127.0.0.1:5555/callback" \
>```

More info on this in later sections, but might be different for your needs.

### Add dex repo to helm

```
helm repo add oidc https://charts.dexidp.io
```

### Run helm upgrade / install

```
# set your domain
export DOMAIN="example.com"

# TIPS:
# helm show values stable/dex | yq
# use `noglob` on mac: https://stackoverflow.com/questions/63327027/slice-in-helm-no-matches-found
# --version is the CHART version `helm search repo oidc`

noglob helm upgrade -i dex-helm oidc/dex \
--namespace "auth-system" \
--create-namespace \
--version "0.14.0" \
--set https.enabled=true \
--set ingress.enabled=true \
--set ingress.className=nginx \
--set ingress.hosts[0].host="dex2.${DOMAIN}" \
--set ingress.hosts[0].paths[0].path="/" \
--set ingress.hosts[0].paths[0].pathType="ImplementationSpecific" \
--set ingress.tls[0].hosts[0]="dex2.${DOMAIN}" \
--set volumes[0].name="tls" \
--set volumes[0].csi.driver="csi.cert-manager.io" \
--set volumes[0].csi.readOnly=true \
--set volumes[0].csi.volumeAttributes."csi\.cert-manager\.io\/issuer-name"="digitalocean-issuer-prod" \
--set volumes[0].csi.volumeAttributes."csi\.cert-manager\.io\/issuer-kind"="ClusterIssuer" \
--set volumes[0].csi.volumeAttributes."csi\.cert-manager\.io\/dns-names"="dex2.${DOMAIN}" \
--set volumes[0].csi.volumeAttributes."csi\.cert-manager\.io\/certificate-file"="tls.crt" \
--set volumes[0].csi.volumeAttributes."csi\.cert-manager\.io\/privatekey-file"="tls.key" \
--set volumeMounts[0].name=tls \
--set volumeMounts[0].mountPath="/etc/crt" \
--set volumeMounts[0].readOnly=true \
--set config.enablePasswordDB=false \
--set config.storage.type=memory \
--set config.web.https="0.0.0.0:5554" \
--set config.web.tlsCert="/etc/crt/tls.crt" \
--set config.web.tlsKey="/etc/crt/tls.key" \
--set config.issuer="https://dex2.${DOMAIN}" \
--set config.connectors[0].type="github" \
--set config.connectors[0].id="github" \
--set config.connectors[0].name="GitHub" \
--set config.connectors[0].config.clientID="${CLIENT_ID}" \
--set config.connectors[0].config.clientSecret="${CLIENT_SECRET}" \
--set config.connectors[0].config.redirectURI="https://dex2.${DOMAIN}/callback" \
--set config.staticClients[0].id="kubelogin-test" \
--set config.staticClients[0].redirectURIs[0]="http://localhost:8000" \
--set config.staticClients[0].redirectURIs[1]="http://localhost:18000" \
--set config.staticClients[0].redirectURIs[2]="http://127.0.0.1:5555/callback" \
--set config.staticClients[0].name="Testing OIDC" \
--set config.staticClients[0].secret="ZXhhbXBsZS1hRANDOMSTRINGcHAtc2VjcmV0" \
-f - <<EOF 
ingress:
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
EOF

# The helm chart today doesn't support using the HTTPS port in the ingress controller yet (ref: github.com/dexidp/helm-charts/issues/15)
# So let's patch it
kubectl -n auth-system patch ing/dex-helm --type=json -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/port/number", "value":5554}]'
```

> Note: `ingress.tls[0].hosts[0]` isn't technically used, but without it, helm spits out a http (no-https) url. I think it could be removed with little to no impact.

### Switch context to use `auth-system` namespace

```
kubectl config set-context --current --namespace=auth-system
```

Validate cert is not `pending` with:

```
kubectl get orders --watch
```

Once the order is `valid` check Dex at (replace domain): https://dex2.compute.rip/.well-known/openid-configuration

### Test with `kubelogin`

Putting it all together, use [kubelogin](https://github.com/int128/kubelogin), a kubectl plugin for Kubernetes OpenID Connect authentication (kubectl oidc-login).

Installing the plugin with `brew` automatically adds it to my path and I can leverage it by updating my kubeconfig.

```
# install kubelogin
brew install int128/kubelogin/kubelogin
```

Create a KUBECONFIG user named oidc ("set-credentials") with our config. This does not overwrite your current user and you can switch between users for testing.

```
# create a user named "oidc"
kubectl config set-credentials oidc \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url="https://dex2.compute.rip" \
  --exec-arg=--oidc-client-id="kubelogin-test" \
  --exec-arg=--oidc-extra-scope="email" \
  --exec-arg=--oidc-client-secret="ZXhhbXBsZS1hRANDOMSTRINGcHAtc2VjcmV0"
```

You now have 2 users in your KUBECONFIG ("oidc" and "kubernetes-admin"). Let's switch to our user for testing:

```
# switch to the oidc user
kubectl config set-context --current --user=oidc

# should open a browser to login
kuebctl get pods -A
error: You must be logged in to the server (Unauthorized)
```

As expected, since we don't have any permissions. Let's give us some:

```
# switch back to working cluster admin
kubectl config set-context --current --user=kubernetes-admin

# create cluster role binding for testing using my GitHub email as the user scope
kubectl create clusterrolebinding oidc-cluster-admin --clusterrole=cluster-admin --user='mypersonalemail@gmail.com'
```

Test again:

```
# use the oidc user
kubectl config set-context --current --user=oidc

# get all pods
kubectl get pods -A
```

Expected output should be similar to:

```
auth-system     dex-helm-d78d99c5b-96sw4                                 1/1     Running   0              105m
cert-manager    cert-manager-64f9f45d6f-qglzc                            1/1     Running   3 (106m ago)   2d22h
cert-manager    cert-manager-cainjector-56bbdd5c47-zrszz                 1/1     Running   3 (106m ago)   2d22h
cert-manager    cert-manager-csi-driver-2w2rt                            3/3     Running   0              2d17h
cert-manager    cert-manager-csi-driver-8qmk6                            3/3     Running   0              2d17h
cert-manager    cert-manager-webhook-d4f4545d7-nbwgx                     1/1     Running   0              2d22h
ingress-nginx   ingress-nginx-controller-74b9fffff9-qrv2n                1/1     Running   0              2d17h
kube-system     cilium-9bh82                                             1/1     Running   0              2d23h
kube-system     cilium-gm22n                                             1/1     Running   0              2d23h
kube-system     cilium-operator-56486f49cd-dhf9k                         1/1     Running   4 (106m ago)   2d23h
kube-system     cilium-operator-56486f49cd-k6l7v                         1/1     Running   4 (107m ago)   2d23h
kube-system     cilium-xhnrm                                             1/1     Running   0              2d23h
kube-system     coredns-787d4945fb-6c252                                 1/1     Running   0              2d23h
kube-system     coredns-787d4945fb-9jvqw                                 1/1     Running   0              2d23h
kube-system     digitalocean-cloud-controller-manager-7df847754f-bcwrw   1/1     Running   0              2d23h
kube-system     etcd-control-plane-nyc3-1                                1/1     Running   0              2d23h
kube-system     kube-apiserver-control-plane-nyc3-1                      1/1     Running   0              106m
kube-system     kube-controller-manager-control-plane-nyc3-1             1/1     Running   4 (107m ago)   2d23h
kube-system     kube-proxy-626n7                                         1/1     Running   0              2d23h
kube-system     kube-proxy-7sk5f                                         1/1     Running   0              2d23h
kube-system     kube-proxy-v8hqf                                         1/1     Running   0              2d23h
kube-system     kube-scheduler-control-plane-nyc3-1                      1/1     Running   4 (107m ago)   2d23h
```

It works! 🎉🎉🎉 Happy auth-ing!

### Troubleshooting

Below are a few helpful ideas that I used to resolve issues I've came across.

Looking at the most recent events across all namespaces is a quick check for issues:

```
kubectl get events --sort-by='.metadata.creationTimestamp' -A
```

Made a URL change? Don't forget to update the GitHub oauth app. You can also clear the `kubectl` cache:

```
rm -rf $HOME/.kube/cache
rm -rf $HOME/.kube/http-cache
```

Ingress woes?

```
# look at ingress configuration
kubectl exec deploy/ingress-nginx-controller -n ingress-nginx -- cat nginx.conf
```

Stuck? Take a look at your friendly container logs:

```
# Ingress
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx 

# API server
kubectl logs -n kube-system -l component=kube-apiserver

# dex
kubectl logs -n auth-system -l app.kubernetes.io/name=dex 
```

**IMPORTANT:** The CSI Driver requests a certificate on creation and Let's Encrypt only allows 5 requests every 168 hours. This can result in a pod not spinning up as the CSI volumes happen before image pull.

If you request too many certs, you'll notice the container doesn't start and a `describe` of the dex pod shows the error:

> Failed to create Order: 429 urn:ietf:params:acme:error:rateLimited: Error creating new order :: too many certificates (5) already issued for this exact set of domains in the last 168 hours:

Lastly, if you want to see the exact data being transmitted or validate the configuration is working outside the Kubernetes API. Deploy dex's sample application (https://dexidp.io/docs/kubernetes/#logging-into-the-cluster). The sample application is a go http app that you "login" to dex with. The resulting webpage contains similar information like:

```
ID Token: [ REDACTED ]

Access Token: [ REDACTED ]

Claims:

{
  "iss": "[ REDACTED ]",
  "sub": "[ REDACTED ]",
  "aud": "kubelogin-test",
  "exp": 1680104333,
  "iat": 1680017933,
  "at_hash": "[ REDACTED ]",
  "c_hash": "[ REDACTED ]",
  "email": "[ REDACTED ]",
  "email_verified": true,
  "name": "Jim Angel",
  "preferred_username": "jimangel"
}

Refresh Token: [ REDACTED ]
```

To install the example app:

```
git clone git clone https://github.com/dexidp/dex.git && cd dex/examples/example-app

go install .

# create the LE certs locally
curl https://letsencrypt.org/certs/isrgrootx1.pem.txt > /tmp/isrgrootx1.pem.txt
curl https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt > /tmp/lets-encrypt-x3-cross-signed.pem.txt
cat /tmp/isrgrootx1.pem.txt /tmp/lets-encrypt-x3-cross-signed.pem.txt > /tmp/letsencrypt.pem

# run the example app
example-app --issuer https://dex2.compute.rip --issuer-root-ca /tmp/letsencrypt.pem --client-id "kubelogin-test" --client-secret "ZXhhbXBsZS1hRANDOMSTRINGcHAtc2VjcmV0"
```

A page appears with fields such as scope and client-id. For the most basic case these are not required, so leave the form blank. Click login.

### Cleanup

```
helm delete dex-helm --namespace "auth-system"
```