Source: https://github.com/digitalocean/digitalocean-cloud-controller-manager/blob/master/docs/getting-started.md

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
kubectl apply -f https://raw.githubusercontent.com/digitaloceandigitalocean-cloud-controller-manager/master/releases/v0.1.24.yml
```

### Example service (nginx LB on port 80)

```
kubectl apply -f https://raw.githubusercontent.com/digitalocean/digitalocean-cloud-controller-manager/master/docs/controllers/services/examples/http-nginx.yml
```

> **NOTE:** you need to delete your services to have them properly removed. If you destroy the cluster (delete the droplets), you will need to delete the LB's from the DigitalOcean GUI.

### More examples

https://github.com/digitalocean/digitalocean-cloud-controller-manager/tree/master/docs/controllers/services/examples