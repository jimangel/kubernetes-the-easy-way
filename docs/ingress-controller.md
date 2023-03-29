Source: https://kubernetes.github.io/ingress-nginx/deploy/#using-helm
Source: `helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx | yq`

### Pre-reqs

- Helm v3 [installed](https://helm.sh/docs/intro/install/)
- DigitalOcean [Cloud Controller Manager](add-digitalocean-ccm.md) deployed
- Ability to create DNS records for a public domain

Before you start, make sure your domain is setup to use DNS. I'm using DigitalOcean. You could use Cloudflare or your domain providers DNS. For help, Google "how to create TXT record with YOUR_DNS_PROVIDER."

**Note:** There are no charges for DNS management in DigitalOcean.

If configuring your domain for the first time, it might take up to 24 hours for DNS propagate.

### Install ingress controllers using helm

If still SSHed into the control plane, `exit` back to your terminal.

While we do have the digitalocean CCM installed, that only provisions the LB. There are special annotations (https://github.com/digitalocean/digitalocean-cloud-controller-manager/blob/master/docs/controllers/services/annotations.md) that are supported for services. Including an example for [using digital ocean with ingress-nginx](https://github.com/kubernetes/ingress-nginx/blob/main/hack/manifest-templates/provider/do/values.yaml).

The biggest takeaway is enabling the proxy-protocol AND enabling it via config (covered below). The rest would be workload dependant.

1) Install ingress controllers using default TLS cert

    ```
    helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --set controller.publishService.enabled=true \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-enable-proxy-protocol"=true \
    --set controller.config.use-proxy-protocol=true \
    --set controller.ingressClassResource.name=nginx \
    --set controller.ingressClassResource.name=nginx \
    --set controller.extraArgs.enable-ssl-passthrough=true \
    --namespace ingress-nginx --create-namespace
    ```

    > `controller.extraArgs.enable-ssl-passthrough` is used for https://kubernetes.github.io/ingress-nginx/user-guide/tls/#ssl-passthrough
    
    > `controller.ingressClassResource.name=nginx` is the default class name used in `spec.ingressClassName` but it's good to have the ability to change here too.
    
    Switch context to use namespace
    
    ```
    kubectl config set-context --current --namespace=ingress-nginx
    ```

### Configure DNS

Wait for ingress service LoadBalancer `<pending>` EXTERNAL-IP to be generated.

```
kubectl --namespace ingress-nginx get services -o wide -w ingress-nginx-controller
NAME                                  TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
nginx-nginx-ingress-controller        LoadBalancer   10.97.183.148    <pending>     80:30511/TCP,443:31594/TCP   30s
```

Create two DNS A records with the value of your IP.
- Create an A record with the hostname `*`
- Create an A record with the hostname `@`

The `*` record will direct all subdomains to your loadbalancer and the `@` record will direct all domain (example.com) traffic to the loadbalancer.

Example:

![](img/dns.png)


### Test with a dummy nginx container

Set namespace context

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

Create an ingress object to accept external traffic.

```
# replace example.com with your domain
export DOMAIN="example.com"

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test
spec:
  ingressClassName: nginx
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

Visit URL (test.example.com) in a web browser.

### Clean up

Ensure namespace context

```
kubectl config set-context --current --namespace=default
```

Delete the nginx test deployment

```
kubectl delete deployment nginx
kubectl delete service nginx
kubectl delete ingress test
```

(optionally) Delete the ingress controllers

```
helm delete ingress-nginx --namespace ingress-nginx
```