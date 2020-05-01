#### TODO ####
# drop some of the kubeadm tweaks
# lock-in versions of all components
# containerd swap
# s/cgroupfs/systemd
# security
# multi-master
# block storage

#### SET VARIABLES ####

variable "kubernetes_version" { default = "1.18.2" }
variable "pod_subnet" { default = "10.217.0.0/16" }
variable "do_token" {}
variable "pub_key" {}
variable "pvt_key" {}
variable "ssh_fingerprint" {}

#### CONFIGURE CLOUD PROVIDER ####

provider "digitalocean" {
  token = var.do_token
}

#### CREATE CONTROL PLANE NODES ####

resource "digitalocean_droplet" "control_plane" {
  count              = 1
  image              = "ubuntu-18-04-x64"
  name               = format("control-plane-%v", count.index + 1)
  region             = "nyc3"
  size               = "2gb"
  private_networking = true
  ssh_keys = [
    var.ssh_fingerprint,
  ]

connection {
    user        = "root"
    host        = self.ipv4_address
    type        = "ssh"
    private_key = file(var.pvt_key)
    timeout     = "2m"
    agent       = false
  }

#### RENDER KUBEADM CONFIG ####

provisioner "file" {
  content = templatefile("${path.module}/kubeadm-config.tpl", { kubernetes_version = var.kubernetes_version, pod_subnet = var.pod_subnet, control_plane_ip = digitalocean_droplet.control_plane[0].ipv4_address })
  destination = "/tmp/kubeadm-config.yaml"
  }

provisioner "remote-exec" {
  inline = [
      #  GENERAL REPO SPEEDUP
      "echo '' > /etc/apt/sources.list",
      "add-apt-repository 'deb [arch=amd64] http://mirrors.digitalocean.com/ubuntu/ bionic main restricted'",
      # ADD KUBERNETES REPO
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -",
      "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      # INSTALL KUBEADM PRE-REQS
      "apt update && sudo apt install -y apt-transport-https -f",
      # KUBEADM TWEAKS
      "modprobe br_netfilter",
      "printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n' > /etc/sysctl.d/k8s.conf",
      "sysctl --system",
      # INSTALL DOCKER
      "curl -L https://get.docker.io | sudo bash",
      # INSTALL KUBEADM
      "apt install -y kubectl=${var.kubernetes_version}-00 kubelet=${var.kubernetes_version}-00 kubeadm=${var.kubernetes_version}-00 -f",
      # KUBEADM INIT THE CONTROL PLANE
      "kubeadm init --config=/tmp/kubeadm-config.yaml"
    ]
  }

provisioner "remote-exec" {
  inline = [
    # INSTALL CALICO CNI
    "mkdir -p /root/.kube",
    "cp -i /etc/kubernetes/admin.conf /root/.kube/config",
    "chown $(id -u):$(id -g) /root/.kube/config",
    "kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.7/install/kubernetes/quick-install.yaml"
    ]
  }
}

#### CREATE WORKER NODES ####

resource "digitalocean_droplet" "worker" {
count              = 2
image              = "ubuntu-18-04-x64"
name               = format("worker-%v", count.index + 1)
region             = "nyc3"
size               = "2gb"
private_networking = true
ssh_keys = [
  var.ssh_fingerprint,
]

connection {
  user        = "root"
  host        = self.ipv4_address
  type        = "ssh"
  private_key = file(var.pvt_key)
  timeout     = "2m"
  agent       = false
  }

#### RENDER KUBEADM CONFIG ####

provisioner "file" {
  content = templatefile("${path.module}/kubeadm-config.tpl", { kubernetes_version = var.kubernetes_version, pod_subnet = var.pod_subnet, control_plane_ip = digitalocean_droplet.control_plane[0].ipv4_address })
  destination = "/tmp/kubeadm-config.yaml"
  } 

provisioner "remote-exec" {
  inline = [
      #  GENERAL REPO SPEEDUP
      "echo '' > /etc/apt/sources.list",
      "add-apt-repository 'deb [arch=amd64] http://mirrors.digitalocean.com/ubuntu/ bionic main restricted'",
      # ADD KUBERNETES REPO
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -",
      "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      # INSTALL KUBEADM PRE-REQS
      "apt update && sudo apt install -y apt-transport-https -f",
      # KUBEADM TWEAKS
      "modprobe br_netfilter",
      "printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n' > /etc/sysctl.d/k8s.conf",
      "sysctl --system",
      # INSTALL DOCKER
      "curl -L https://get.docker.io | sudo bash",
      # INSTALL KUBEADM
      "apt install -y kubectl=${var.kubernetes_version}-00 kubelet=${var.kubernetes_version}-00 kubeadm=${var.kubernetes_version}-00 -f",
      # KUBEADM JOIN THE WORKER
      "kubeadm join --config=/tmp/kubeadm-config.yaml"
    ]
  }
}

#### OUTPUT VARIABLES ####

output "control_plane_ip" {
  value = digitalocean_droplet.control_plane.*.ipv4_address
}

output "worker_ip" {
  value = digitalocean_droplet.worker.*.ipv4_address
}