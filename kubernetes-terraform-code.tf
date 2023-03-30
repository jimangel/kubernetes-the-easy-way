##############
#### TODO ####
##############

# containerd swap
# security
# multi-master
# block storage

##################################
#### SET VARIABLES & VERSIONS ####
##################################

# https://github.com/kubernetes/sig-release/blob/master/releases/patch-releases.md#timelines
variable "kubernetes_version" { default = "1.26.3" }

# Note: Cilium no longer releases a deployment file and rely on helm now.
# to generate:
# helm repo add cilium https://helm.cilium.io/ && helm repo update
# helm template cilium cilium/cilium --version 1.13.1 --namespace kube-system > cilium-install.yaml
# https://github.com/cilium/cilium/releases

variable "pod_subnet" { default = "10.217.0.0/16" }

# https://www.digitalocean.com/docs/platform/availability-matrix/#datacenter-regions
variable "dc_region" { default = "nyc3" }

# https://docs.digitalocean.com/reference/api/api-reference/#operation/sizes_list
# curl -X GET -H "Authorization: Bearer $DO_PAT" "https://api.digitalocean.com/v2/sizes" | jq | grep cpu
# setting below 2 CPUs will fail kubeadm, ignore with `--ignore-preflight-errors=all`
variable "droplet_size" { default = "s-2vcpu-2gb" }

# set image
# curl -X GET --silent "https://api.digitalocean.com/v2/images?per_page=999" -H "Authorization: Bearer $DO_PAT" | jq | grep ubuntu  
variable "do_image" { default = "ubuntu-22-04-x64"}

# set with `export DO_PAT=<API TOKEN>`
variable "do_token" {}

# used for SSH access to nodes (pub on created, pvt for config)
variable "pub_key" {}
variable "pvt_key" {}

##################################
#### CONFIGURE CLOUD PROVIDER ####
##################################

provider "digitalocean" { token = var.do_token }

###########################################################
#### GENERATE RANDOM STRING FOR UNIQUE KUBECTL CONTEXT ####
###########################################################

resource "random_string" "lower" {
  length  = 6
  upper   = false
  lower   = true
  numeric  = true
  special = false
}

######################################
#### CREATE CONTROL PLANE NODE(S) ####
######################################

resource "digitalocean_droplet" "control_plane" {
  count              = 1
  image              = var.do_image
  name               = format("control-plane-%s-%v", var.dc_region, count.index + 1)
  region             = var.dc_region
  size               = var.droplet_size
  user_data          = <<EOF
#cloud-config
ssh_pwauth: false
users:
  - name: kubernetes
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
    ssh-authorized-keys:
      - "${file("${var.pub_key}")}"
EOF

  connection {
    user           = "kubernetes"
    host           = self.ipv4_address
    type           = "ssh"
    agent          = false
    agent_identity = var.pub_key
    private_key    = "${file("${var.pvt_key}")}"
    timeout        = "15m"
  }

  ###############################################
  ### RENDER KUBEADM CONFIG TO CONTROL PLANE ####
  ###############################################
  provisioner "file" {
      content = templatefile("${path.module}/kubeadm-config.tpl", 
      {
        cluster_name = format("ktew-%s", var.dc_region),
        kubernetes_version = var.kubernetes_version,
        pod_subnet = var.pod_subnet,
        control_plane_ip = digitalocean_droplet.control_plane[0].ipv4_address 
      })
      destination = "/tmp/kubeadm-config.yaml"
  }
  
  ###################################################
  #### INSTALL CONTROL PLANE DOCKER / KUBERNETES ####
  ###################################################
  
  # https://kubernetes.io/docs/setup/production-environment/container-runtimes/#install-and-configure-prerequisites
  # helpful for debugging containerd: `crictl --debug version`
  # more: `ctr plugin list | grep cri`

  provisioner "remote-exec" {
    inline = [
      # GENERAL REPO SPEEDUP
      "until [ -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "echo '' | sudo tee /etc/apt/sources.list",
      "sudo add-apt-repository -y 'deb http://mirrors.digitalocean.com/ubuntu/ jammy main restricted universe'",
      # ADD KUBERNETES REPO
      "sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
      # INSTALL containerd
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable' | sudo tee /etc/apt/sources.list.d/docker.list",
      "sudo apt update && sudo apt install containerd.io -y",
      "containerd config default | sudo tee /etc/containerd/config.toml",
      "sudo sed -i 's~SystemdCgroup = false~SystemdCgroup = true~g' /etc/containerd/config.toml",
      "sudo systemctl enable containerd",
      # fix crictl (avoids deprecated failure error around dockershim)
      "printf 'runtime-endpoint: unix:///run/containerd/containerd.sock' | sudo tee /etc/crictl.yaml",
      # containerd CNI
      "curl -Lo 'cni-plugins-linux.tgz' https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz",
      "sudo mkdir -p /opt/cni/bin",
      "sudo tar Cxzvf /opt/cni/bin cni-plugins-linux.tgz",
      "sudo systemctl restart containerd",
      # KUBEADM TWEAKS
      "printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf",
      "sudo modprobe overlay",
      "sudo modprobe br_netfilter",
      "printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n' | sudo tee /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system",
      # INSTALL KUBEADM
      "sudo apt install -y kubectl=${var.kubernetes_version}-00 kubelet=${var.kubernetes_version}-00 kubeadm=${var.kubernetes_version}-00 -f",
      # sudo apt install -y kubectl=1.26.3-00 kubelet=1.26.3-00 kubeadm=1.26.3-00 -f
      # KUBEADM INIT THE CONTROL PLANE
      "sudo kubeadm init --config=/tmp/kubeadm-config.yaml",
      # SETUP KUBECTL REMOTELY
      "mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config"
    ]
  }

  #####################
  #### INSTALL CNI ####
  #####################
  provisioner "file" {
    source      = "cilium-install.yaml"
    destination = "/tmp/cilium-install.yaml"
  }
  
  provisioner "remote-exec" {
    inline = [
      # INSTALL CILIUM CNI
      "kubectl apply -f /tmp/cilium-install.yaml"
      ]
    }
}

#############################
#### CREATE WORKER NODES ####
#############################
resource "digitalocean_droplet" "worker" {
  count              = 2
  image              = var.do_image
  name               = format("worker-%s-%v", var.dc_region, count.index + 1)
  region             = var.dc_region
  size               = var.droplet_size
  user_data          = <<EOF
#cloud-config
ssh_pwauth: false
users:
  - name: kubernetes
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
    ssh-authorized-keys:
      - "${file("${var.pub_key}")}"
EOF

  connection {
    user           = "kubernetes"
    host           = self.ipv4_address
    type           = "ssh"
    agent          = false
    agent_identity = var.pub_key
    private_key    = "${file("${var.pvt_key}")}"
    timeout        = "15m"
  }

  ###############################################
  #### RENDER KUBEADM CONFIG TO WORKER NODES ####
  ###############################################
  provisioner "file" {
    content = templatefile("${path.module}/kubeadm-config.tpl", 
      {
        cluster_name = format("ktew-%s", var.dc_region),
        kubernetes_version = var.kubernetes_version,
        pod_subnet = var.pod_subnet,
        control_plane_ip = digitalocean_droplet.control_plane[0].ipv4_address 
      })
      destination = "/tmp/kubeadm-config.yaml"
    }
  
  ############################################
  #### INSTALL WORKER DOCKER / KUBERNETES ####
  ############################################
  provisioner "remote-exec" {
    inline = [
      # GENERAL REPO SPEEDUP
      "until [ -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "echo '' | sudo tee /etc/apt/sources.list",
      "sudo add-apt-repository -y 'deb http://mirrors.digitalocean.com/ubuntu/ jammy main restricted universe'",
      # ADD KUBERNETES REPO
      "sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
      # INSTALL containerd
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable' | sudo tee /etc/apt/sources.list.d/docker.list",
      "sudo apt update && sudo apt install containerd.io -y",
      "containerd config default | sudo tee /etc/containerd/config.toml",
      "sudo sed -i 's~SystemdCgroup = false~SystemdCgroup = true~g' /etc/containerd/config.toml",
      "sudo systemctl enable containerd",
      # fix crictl (avoids deprecated failure error around dockershim)
      "printf 'runtime-endpoint: unix:///run/containerd/containerd.sock' | sudo tee /etc/crictl.yaml",
      # containerd CNI
      "curl -Lo 'cni-plugins-linux.tgz' https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz",
      "sudo mkdir -p /opt/cni/bin",
      "sudo tar Cxzvf /opt/cni/bin cni-plugins-linux.tgz",
      "sudo systemctl restart containerd",
      # KUBEADM TWEAKS
      "printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf",
      "sudo modprobe overlay",
      "sudo modprobe br_netfilter",
      "printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n' | sudo tee /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system",
      # INSTALL KUBEADM
      "sudo apt install -y kubectl=${var.kubernetes_version}-00 kubelet=${var.kubernetes_version}-00 kubeadm=${var.kubernetes_version}-00 -f",
      # sudo apt install -y kubectl=1.26.3-00 kubelet=1.26.3-00 kubeadm=1.26.3-00 -f
      # KUBEADM JOIN THE WORKER
      "sudo kubeadm join --config=/tmp/kubeadm-config.yaml"
    ]
  }
}


##########################
#### OUTPUT VARIABLES ####
##########################

output "control_plane_ip" {
  value = digitalocean_droplet.control_plane.*.ipv4_address
}

output "worker_ip" {
  value = digitalocean_droplet.worker.*.ipv4_address
}

output "cluster_context" {
  value = format("ktew-%s-%s", random_string.lower.result, var.dc_region)
  description = "kubectl config use-context --context ..."
}
