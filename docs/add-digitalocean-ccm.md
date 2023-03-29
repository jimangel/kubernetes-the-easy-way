Source: https://github.com/digitalocean/digitalocean-cloud-controller-manager/blob/master/docs/getting-started.md

The cloud-controller-manager is a Kubernetes control plane component that embeds cloud-specific control logic. The cloud controller manager lets you link your cluster into your cloud provider’s API, and separates out the components that interact with that cloud platform from components that just interact with your cluster.

By adding the DigitalOcean CCM, you can use the service type `LoadBalancer` which will automatically provision and destroy DigitalOcean Load Balancers.

### Create secret

```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: digitalocean
  namespace: kube-system
stringData:
  access-token: $DO_PAT
EOF
```

### Deploy CCM

```
kubectl apply -f https://raw.githubusercontent.com/digitalocean/digitalocean-cloud-controller-manager/master/releases/v0.1.42.yml
```

At this point, I would skip to creating the [ingress-controller](ingress-controller.md). However, the following sections cover general testing.

### Example service (nginx app with DigitalOcean load balancer on port 80)

```
kubectl config set-context --current --namespace=default

kubectl apply -f https://raw.githubusercontent.com/digitalocean/digitalocean-cloud-controller-manager/master/docs/controllers/services/examples/http-nginx.yml

# check with `kubectl get svc`
```

**NOTE:** you need to delete your services to have them properly removed. If you destroy the cluster (delete the droplets), you will need to delete the LB's from the DigitalOcean GUI.

### Clean up

```
kubectl delete -f https://raw.githubusercontent.com/digitalocean/digitalocean-cloud-controller-manager/master/docs/controllers/services/examples/http-nginx.yml
```

### More example YAML

https://github.com/digitalocean/digitalocean-cloud-controller-manager/tree/master/docs/controllers/services/examples
and
https://github.com/digitalocean/digitalocean-cloud-controller-manager/blob/master/docs/controllers/services/examples/README.md