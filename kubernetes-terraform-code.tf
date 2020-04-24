#### TODO ####
# custom-kubeadm config (kubelet, API, PSP, audit, etc)
# containerd
# automate version k8s (https://storage.googleapis.com/kubernetes-release/release/stable.txt)
# speed up
# secure with kube-bench / kube-hunter / firewall rules
# multi-master
# LB
# block storage
# clean up kubeadm errors
# disable swap

#### SET VARIABLES ####

variable "do_token" {}
variable "pub_key" {}
variable "pvt_key" {}
variable "ssh_fingerprint" {}
#varible "k8s_version" {}

#### CONFIGURE PROVIDER ####

provider "digitalocean" {
  token = var.do_token
}

#### CREATE CONTROL PLANE NODES ####

resource "digitalocean_droplet" "control_plane" {
  count              = 1
  image              = "ubuntu-18-04-x64"
  name               = format("control-plane-%v", count.index + 1)
  region             = "nyc3"
  #size               = "512mb"
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

provisioner "local-exec" {
    command = "echo ${self.name} IP-ADDRESS == ${self.ipv4_address} >> info.txt"
  }

 provisioner "remote-exec" {
    inline = [
      # add remote repos (docker, kubernetes)
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable'",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -",
      "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      "sudo apt update && sudo apt install -y apt-transport-https -f",
      # install docker
      "sudo apt install docker-ce -y -f",
      # install kubernetes components
      "sudo apt install -y kubectl=1.18.2-00 kubelet=1.18.2-00 kubeadm=1.18.2-00 -f",
      # initialize the Master node.
      "kubeadm init  --kubernetes-version v1.18.2 --pod-network-cidr=10.217.0.0/16 --token=ff6edf.38d10317aa6fa57e --ignore-preflight-errors=all"
    ]
 }

 provisioner "remote-exec" {
    inline = [
      "mkdir -p /root/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config",
      "sudo chown $(id -u):$(id -g) /root/.kube/config",
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

provisioner "local-exec" {
    command = "echo ${self.name} IP-ADDRESS == ${self.ipv4_address} >> info.txt"
  }


 provisioner "remote-exec" {
    inline = [
      # add remote repos (docker, kubernetes)
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -",
      "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable'",
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -",
      "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      "sudo apt update && sudo apt install -y apt-transport-https -f",
      # install docker
      "sudo apt install docker-ce -y -f",
      # install kubernetes components
      "sudo apt install -y kubectl=1.18.2-00 kubelet=1.18.2-00 kubeadm=1.18.2-00 -f",
      # join cluster
      "kubeadm join --ignore-preflight-errors=all --token ff6edf.38d10317aa6fa57e '${digitalocean_droplet.control_plane[0].ipv4_address}':6443 --discovery-token-unsafe-skip-ca-verification"
    ]
 }

}

#### OUTPUT VARIABLES FOR USE ####

output "control_plane_ip" {
  value = digitalocean_droplet.control_plane.*.ipv4_address
}

output "worker_ip" {
  value = digitalocean_droplet.worker.*.ipv4_address
}