variable "do_token" {}
variable "atlas_token" {}
variable "ssh_fingerprint" {}
variable "ssh_private" {}
variable "ssh_public" {}

atlas {
  name = "orclev/digitalocean"
}

provider "digitalocean" {
  token = "${var.do_token}"
}

resource "digitalocean_droplet" "nomad_master" {
  name = "nomad-master"
  size = "512mb"
  image = "coreos-alpha"
  region = "nyc3"
  ipv6 = true
  private_networking = true
  backups = false
  ssh_keys = [1525856,"${digitalocean_ssh_key.terraform.id}"]
  connection {
    type = "ssh"
    user = "core"
    #host = "nomad-master.tenletters.org"
    private_key = "${var.ssh_private}"
    timeout = "5m"
    agent = false
  }

  provisioner "file" {
    source = "server.conf"
    destination = "/tmp/server.conf"
  }

  provisioner "file" {
    source = "consul_server.conf"
    destination = "/tmp/consul_server.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/NOMAD_RPC/${digitalocean_droplet.nomad_master.ipv4_address_private}:4647/g' /tmp/server.conf",
      "sudo sed -i 's/NOMAD_HTTP/${digitalocean_droplet.nomad_master.ipv4_address}:4646/g' /tmp/server.conf",
      "sudo sed -i 's/NOMAD_SERF/${digitalocean_droplet.nomad_master.ipv4_address_private}:4648/g' /tmp/server.conf",
      "sudo sed -i 's/ATLAS_TOKEN/${var.atlas_token}/g' /tmp/server.conf",
      "sudo mkdir /etc/nomad",
      "sudo mv /tmp/server.conf /etc/nomad/",
      "sudo sed -i 's/ATLAS_TOKEN/${var.atlas_token}/g' /tmp/consul_server.conf",
      "sudo sed -i 's/CONSUL_IP/${digitalocean_droplet.nomad_master.ipv4_address_private}/g' /tmp/consul_server.conf",
      "sudo mkdir /etc/consul",
      "sudo mv /tmp/consul_server.conf /etc/consul/",
      "docker run -d -p 8300:8300 -p 8301:8301 -p 8302:8302 -p 8400:8400 -p 8500:8500 -p 8600:8600 --name consul -v /etc/consul/consul_server.conf:/etc/consul/consul_server.conf voxxit/consul agent -config-file /etc/consul/consul_server.conf",
      "docker run -d --name nomad -v /var/run/docker.sock:/var/run/docker.sock -v /etc/nomad/server.conf:/etc/nomad/server.conf -p 4646:4646 -p 4647:4647 -p 4648:4648 shanesveller/nomad:0.2.2 agent -config /etc/nomad/server.conf"
    ]
  }
}

resource "digitalocean_ssh_key" "terraform" {
  name = "Terraform"
  public_key = "${var.ssh_public}"
}

resource "digitalocean_floating_ip" "nomad_master" {
  region = "nyc3"
  droplet_id = "${digitalocean_droplet.nomad_master.id}"
}

resource "digitalocean_record" "nomad_master" {
  domain = "tenletters.org"
  type = "A"
  name = "nomad-master"
  value = "${digitalocean_floating_ip.nomad_master.ip_address}"
}

resource "digitalocean_droplet" "nomad_slave" {
  name = "nomad-slave"
  size = "512mb"
  image = "coreos-alpha"
  region = "nyc3"
  ipv6 = true
  private_networking = true
  backups = false
  ssh_keys = [1525856,"${digitalocean_ssh_key.terraform.id}"]
  #depends_on = ["digitalocean_droplet.nomad_master"]
  connection {
    type = "ssh"
    user = "core"
    private_key = "${var.ssh_private}"
    timeout = "5m"
    agent = false
  }

  provisioner "file" {
    source = "client.conf"
    destination = "/tmp/client.conf"
  }

  provisioner "file" {
    source = "consul_client.conf"
    destination = "/tmp/consul_client.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/NOMAD_MASTER_ADDR/${digitalocean_droplet.nomad_master.ipv4_address_private}:4647/g' /tmp/client.conf",
      "sudo mkdir /etc/nomad",
      "sudo mv /tmp/client.conf /etc/nomad/",
      "sudo sed -i 's/ATLAS_TOKEN/${var.atlas_token}/g' /tmp/consul_client.conf",
      "sudo sed -i 's/CONSUL_MASTER/${digitalocean_droplet.nomad_master.ipv4_address_private}/g' /tmp/consul_client.conf",
      "sudo mkdir /etc/consul",
      "sudo mv /tmp/consul_client.conf /etc/consul/",
      "docker run -d --name consul -v /etc/consul/consul_client.conf:/etc/consul/consul_client.conf voxxit/consul agent -config-file /etc/consul/consul_client.conf",
      "docker run -d --name nomad -v /var/run/docker.sock:/var/run/docker.sock -v /etc/nomad/client.conf:/etc/nomad/client.conf -p 4646:4646 -p 4647:4647 -p 4648:4648 shanesveller/nomad:0.2.2 agent -config /etc/nomad/client.conf"
    ]
  }
}

resource "digitalocean_record" "nomad_slave" {
  domain = "tenletters.org"
  type = "A"
  name = "nomad-slave"
  value = "${digitalocean_droplet.nomad_slave.ipv4_address}"
}
