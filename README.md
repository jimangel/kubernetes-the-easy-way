# Kubernetes The Easy Way

> WARNING: I'm updating this to work with TF Cloud. The biggest difference is using variables for SSH key data instead of using the "file()" function. Things might not be functional... 

This tutorial walks you through setting up Kubernetes the easy way. This guide is for people looking to bootstrap a cluster not managed by a cloud provider.

"not managed" means the control-plane is managed by you as opposed to a cloud provider. This gives you full control of the cluster's configuration (OIDC, FeatureGates, AuditLogs, etc).

Kubernetes The Easy Way is a complement to [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way). Once you understand the hard way, use this tutorial to expand your knowledge in a multi-node lab.

> The results of this tutorial are not production ready, and may receive limited support from the community, but don't let that stop you from learning!

### Overview

Terraform is used to deploy and destroy a Kubernetes cluster on DigitalOcean via kubeadm. By default, the script deploys 1 control-plane-node and 2 worker-nodes.

The default configuration will create (3) 2CPUx2GB nodes ($15 a month or $0.02232 an hour). I use it to spin up, test, and tear down. Total cost of ownership is $45 a month or $0.067 an hour. If I spun up a cluster and tested for 24 hours then destroyed it, it would cost $1.60 - pretty affordable!

> Note: ONLY TESTED ON UBUNTU 18.04

### Cluster details

* [kubernetes](https://github.com/kubernetes/kubernetes) v1.20.5
* [docker](https://github.com/docker/docker-ce) v20.10.5
* [cilium cni](https://github.com/cilium/cilium) v1.9.5
* [ubuntu](https://ubuntu.com/) 20.04 LTS

### Prerequisites

- Install [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html#install-terraform)

- Export a [DigitalOcean Personal Access Token](https://www.digitalocean.com/docs/apis-clis/api/create-personal-access-token/) with **WRITE** access:

    ```
    export DO_PAT="<DIGITALOCEAN PERSONAL ACCESS TOKEN>"
    ```

### Assumptions

- kubectl is [installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/) locally

- You have a default [SSH key](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-1804):

    ```
    # check by running
    ls -l ~/.ssh/id_rsa.pub

    # if not found, run the following command (enter to take defaults)
    ssh-keygen

    # add the key to your ssh agent
    ssh-add ~/.ssh/id_rsa
    ```
    
    To create and/or use a unique SSH key:

    ```
    # create
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ktew
    ssh-add ~/.ssh/id_rsa_ktew
    
    # use
    export PUBLIC_KEY="~/.ssh/id_rsa_ktew.pub"
    export PRIVATE_KEY="~/.ssh/id_rsa_ktew"
    ```

### Deploy Kubernetes

Clone repository:

```
git clone https://github.com/jimangel/kubernetes-the-easy-way
cd kubernetes-the-easy-way
```


Build the cluster:

```
./create-cluster.sh
```

It should take ~5 minutes to complete

```
real	4m24.201s
user	0m6.580s
sys	0m3.029s
```

Check it out!

```
kubectl get nodes
kubectl get pods -A
```

---

### Smoke test

SSH into any of the nodes
```
# control-plane-1
ssh root@$(terraform output -json control_plane_ip | jq -r .[0])

# worker-1
ssh root@$(terraform output -json worker_ip | jq -r .[0])

# worker-2
ssh root@$(terraform output -json worker_ip | jq -r .[1])
```

Deploy NGINX
```
kubectl create deployment nginx --image=nginx
kubectl expose deployment/nginx --port 80
kubectl port-forward deployment/nginx 8080:80
# visit http://localhost:8080 in a browser
```

Run Cilium connectivity test
```
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.7.2/examples/kubernetes/connectivity-check/connectivity-check.yaml
```

Use cluster context
```
kubectl config use-context $(terraform output cluster_context)
```

---

### Cleaning up

```
./destroy-cluster.sh
```

### Additional resources:

Most of these resources are meant to be completed in order and build on each previous guide.

- How to [add a DigitalOcean CCM](docs/add-digitalocean-ccm.md) for dynamic LB provisioning.
- How to [deploy an ingress controller](docs/ingress-controller.md) for external traffic.
- How to [install cert-manager](docs/certmanager.md) for automatic SSL certs.
- How to [use Dex as an OIDC provider](docs/setup-dex-oidc.md) for kubectl authentication with GitHub.
- How to [deploy the Prometheus Operator](docs/setup-prometheus-operator.md) for monitoring.
- How to [create multi-region clusters](docs/multi-cluster-testing.md) for advanced testing.

(upcoming resources)

- prometheus / grafana
- harbor
