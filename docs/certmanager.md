Source: https://cert-manager.io/docs/installation/kubernetes/

### Pre-reqs

- Helm v3 [installed](https://helm.sh/docs/intro/install/)
- A domain with [DNS managed by DigitalOcean](https://docs.digitalocean.com/products/networking/dns/quickstart/) or https://cloud.digitalocean.com/networking/domains

**Note:** There are no charges for DNS management in DigitalOcean.

If configuring your domain for the first time, it might take up to 24 hours for DNS propagate.

### Install certmanager using helm

```
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade -i \
cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.11.0 \
--set installCRDs=true
```

> https://cert-manager.io/docs/installation/kubernetes/#verifying-the-installation

### Setup ACME LetsEncrypt issuer via DigitalOcean

Switch context to use namespace

```
kubectl config set-context --current --namespace=cert-manager
```

Export your unique variables needed

```
export EMAIL="emailaddress@example.com"
```

```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: digitalocean-dns
  namespace: cert-manager
stringData:
  access-token: $DO_PAT
EOF
```

```
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: digitalocean-issuer-prod
spec:
  acme:
    email: $EMAIL
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource that will be used to store the account's private key.
      name: letsencrypt-prod
    solvers:
    - dns01:
        digitalocean:
          tokenSecretRef:
            name: digitalocean-dns
            key: access-token
EOF
```

Validate status:

```
kubectl describe clusterissuer digitalocean-issuer-prod
```

### Test with a dummy nginx container

Set namespace context back to `default`

```
kubectl config set-context --current --namespace=default
```

Create a nginx deployment

```
kubectl create deployment nginx --image=nginx
```

Create a service (expose) the deployment

```
kubectl expose deployment/nginx --port 80
```

> Note: This exposes the container port, NOT the external "traffic" accepting port. That is defined in the following ingress section.

Create an ingress object to accept external traffic. Using the `force-ssl-redirect` annotation will force HTTPS traffic using our cert.

```
# replace example.com with your domain
export DOMAIN="example.com"

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test
  annotations:
    cert-manager.io/cluster-issuer: digitalocean-issuer-prod
spec:
  ingressClassName: nginx
  tls:                           # placing a host in the TLS config will indicate a certificate should be created
  - hosts:
      - test.${DOMAIN}
    secretName: myingress-cert   # cert-manager will store the created certificate in this secret.
  rules:
  - host: test.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
EOF
```

Wait for certificate to be issued by monitoring `kubectl get orders --watch`. Once STATE is `valid` visit URL (test.example.com) in a web browser.

![](img/ssl-test.png)

### Install CSI Driver for pod-level TLS (optional)

```
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade -i -n cert-manager cert-manager-csi-driver jetstack/cert-manager-csi-driver --wait
```

### Up next

Let's [add an OIDC provider](setup-dex-oidc.md) for authentication.

### Clean up

Ensure `default` namespace context

```
kubectl config set-context --current --namespace=default
```

Delete the nginx test deployment

```
kubectl delete deployment nginx
kubectl delete service nginx
kubectl delete ingress test
```

Delete cert manager:

```
helm delete cert-manager --namespace cert-manager

# optional removal CSI driver
helm delete cert-manager-csi-driver --namespace cert-manager
```