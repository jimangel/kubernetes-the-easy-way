# Kubernetes The Easy Way

This tutorial walks you through setting up Kubernetes the easy way. This guide is for people looking to bootstrap a cluster not managed by a cloud provider.

"not managed" means the control-plane is managed by you as opposed to a cloud provider. This gives you full control of the cluster's configuration (OIDC, FeatureGates, AuditLogs, etc).

Kubernetes The Easy Way is a complement to [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way). Once you understand the hard way, use this tutorial to expand your knowledge in a multi-node lab.

> The results of this tutorial are not production ready, and may receive limited support from the community, but don't let that stop you from learning!

### Overview

Terraform is used to deploy and destroy a Kubernetes cluster on DigitalOcean via kubeadm. By default, the script deploys 1 control-plane-node and 2 worker-nodes.

The default configuration creates (3) 2CPUx2GB nodes ($18 a month or $0.027 an hour each). I use it to spin up, test, and tear down. Total cost of ownership is $54 a month or $0.081 an hour. If I spun up a cluster and tested for 24 hours then destroyed it, it would cost $1.94 - pretty affordable!

> Note: I've written and tested this code on Ubuntu 22.04, PRs are welcome if you'd like this to support other OSes!

### Cluster details

* [kubernetes](https://github.com/kubernetes/kubernetes) v1.32.0
* [containerd](https://containerd.io/) v1.7.2
* [cilium cni](https://github.com/cilium/cilium) v1.16.5
* [ubuntu](https://ubuntu.com/) 22.04 LTS

> Note: https://kubernetes.io/blog/2022/11/18/upcoming-changes-in-kubernetes-1-26/#cri-api-removal

### Assumptions

- kubectl is [installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/) locally

- You have a default [SSH key](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-1804) (for SSH access on the nodes):

    ```
    # check by running
    ls -l $HOME/.ssh/id_ed25519.pub

    # if not found, run the following command (pressing `enter` to take defaults)
    ssh-keygen -t ed25519

    # add the key to your ssh agent
    ssh-add $HOME/.ssh/id_ed25519
    ```
    
    To create and/or use a unique SSH key:

    ```
    # create
    ssh-keygen -t rsa -b 4096 -f $HOME/.ssh/id_ed25519_ktew
    ssh-add $HOME/.ssh/id_ed25519_ktew
    ```

    This SSH key is for authentication to the server(s) and passed via `cloud-init` vs. droplet `ssh_keys` resource in [kubernetes-terraform-code.tf](kubernetes-terraform-code.tf).

### Prerequisites

- Install [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html#install-terraform) (tested on v1.10.3)

- Export a [DigitalOcean Personal Access Token](https://www.digitalocean.com/docs/apis-clis/api/create-personal-access-token/) with **Full Access** (TODO: descope to just droplets / networking):

   ```
   export DO_PAT="<DIGITALOCEAN PERSONAL ACCESS TOKEN>"
   ```

- Export your SSH public key:

   ```
   export TF_VAR_pub_key="$HOME/.ssh/id_ed25519.pub"
   ```

- Export your SSH private key:

   ```
   export TF_VAR_pvt_key="$HOME/.ssh/id_ed25519"
   ```

> Note: "For Ubuntu 22.04, OpenSSH was updated to v8.x and rsa host keys are disabled by default. Either a client key using ecc needs to be used, or reenable rsa on the host side." ([source with other tips](https://github.com/hashicorp/packer/issues/11733#issuecomment-1106545943)). I don't think this applies to my droplets, but worth keeping in mind moving forward.

### Deploy Kubernetes

Clone repository:

```
git clone https://github.com/jimangel/kubernetes-the-easy-way
cd kubernetes-the-easy-way
```


Build the cluster:

```
# checks env vars and runs terraform init / apply
./create-cluster.sh

# Do you want to perform these actions?
# yes
```

It should take ~5 minutes to complete. Once finished, check it out!

```
# copy the cluster-admin kubeconfig from the control plane node
scp -i ${TF_VAR_pvt_key} kubernetes@$(terraform output -json control_plane_ip | jq -r '.[]'):/home/kubernetes/.kube/config ${HOME}/admin.conf

# export the kubeconfig
export KUBECONFIG=${HOME}/admin.conf

# run some commands!
kubectl get nodes
kubectl get pods -A
```

Output sample:

```
% kubectl get nodes
NAME                   STATUS   ROLES           AGE     VERSION
control-plane-nyc3-1   Ready    control-plane   3m47s   v1.32.0
worker-nyc3-1          Ready    <none>          78s     v1.32.0
worker-nyc3-2          Ready    <none>          78s     v1.32.0

% kubectl get pods -A
NAMESPACE     NAME                                           READY   STATUS    RESTARTS   AGE
kube-system   cilium-9wzmj                                   1/1     Running   0          98s
kube-system   cilium-envoy-4trx8                             1/1     Running   0          86s
kube-system   cilium-envoy-kt8nv                             1/1     Running   0          3m57s
kube-system   cilium-envoy-rh2jd                             1/1     Running   0          98s
kube-system   cilium-nfh47                                   1/1     Running   0          86s
kube-system   cilium-operator-799f498c8-djrdk                1/1     Running   0          3m57s
kube-system   cilium-operator-799f498c8-kslzj                1/1     Running   0          3m57s
kube-system   cilium-sjwqc                                   1/1     Running   0          3m57s
kube-system   coredns-668d6bf9bc-nc7pw                       1/1     Running   0          3m57s
kube-system   coredns-668d6bf9bc-s7qs9                       1/1     Running   0          3m57s
kube-system   etcd-control-plane-nyc3-1                      1/1     Running   0          4m1s
kube-system   kube-apiserver-control-plane-nyc3-1            1/1     Running   0          4m1s
kube-system   kube-controller-manager-control-plane-nyc3-1   1/1     Running   0          4m1s
kube-system   kube-proxy-2lf26                               1/1     Running   0          98s
kube-system   kube-proxy-2r47b                               1/1     Running   0          3m57s
kube-system   kube-proxy-lb4d9                               1/1     Running   0          86s
kube-system   kube-scheduler-control-plane-nyc3-1            1/1     Running   0          4m1s
```

---

### Smoke test

SSH into any of the nodes
```
# control-plane-1
ssh -i ${TF_VAR_pvt_key} kubernetes@$(terraform output -json control_plane_ip | jq -r '.[]')

# worker-1
ssh -i ${TF_VAR_pvt_key} kubernetes@$(terraform output -json worker_ip | jq -r '.[0]')

# worker-2
ssh -i ${TF_VAR_pvt_key} kubernetes@$(terraform output -json worker_ip | jq -r '.[1]')
```

Deploy NGINX
```
kubectl create deployment nginx --image=nginx
kubectl expose deployment/nginx --port 80
kubectl port-forward deployment/nginx 8080:80
# visit http://localhost:8080 in a browser
```

Run Cilium connectivity test:

```
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.16/examples/kubernetes/connectivity-check/connectivity-check.yaml

# check: kubectl get pods --watch
```

The connectivity test should have all pods running `1/1` after some time (under 5 minutes).

Use a cluster context:

```
kubectl config use-context $(terraform output cluster_context)
```

---

### Cleaning up

```
./destroy-cluster.sh

# Do you really want to destroy all resources?
# yes
```

### Additional resources:

Most of these resources are meant to be completed in order and build on each previous guide.

- How to [add a DigitalOcean CCM](docs/add-digitalocean-ccm.md) for dynamic LB provisioning.
- How to [deploy an ingress controller](docs/ingress-controller.md) for external traffic.
- How to [install cert-manager](docs/certmanager.md) for automatic SSL certs.
- How to [use Dex as an OIDC provider](docs/setup-dex-oidc.md) for kubectl authentication with GitHub.
- How to [deploy the Prometheus Operator](docs/setup-prometheus-operator.md) for monitoring.
- How to [create multi-region clusters](docs/multi-cluster-testing.md) for advanced testing.
- [Metrics server](https://artifacthub.io/packages/helm/metrics-server/metrics-server): `noglob helm upgrade --install metrics-server metrics-server/metrics-server --set args[0]='--kubelet-insecure-tls'`

Find the fastest region ping one-liner:

```
{
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-nyc1.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-nyc2.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-nyc3.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-ams2.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-ams3.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-sfo1.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-sfo2.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-sgp1.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-lon1.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-fra1.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-tor1.digitalocean.com/
    curl -w "%{url_effective};%{time_connect}\n" -o /dev/null -s http://speedtest-blr1.digitalocean.com/
} | sort -t';' -k2
```
