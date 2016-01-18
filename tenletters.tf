variable "do_token" {}

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
    private_key = "${file("terraform_rsa")}"
    timeout = "5m"
    agent = false
  }

  provisioner "file" {
    source = "server.conf"
    destination = "/tmp/server.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/NOMAD_RPC/${digitalocean_droplet.nomad_master.ipv4_address_private}:4647/g' /tmp/server.conf",
      "sudo sed -i 's/NOMAD_HTTP/${digitalocean_droplet.nomad_master.ipv4_address}:4646/g' /tmp/server.conf",
      "sudo sed -i 's/NOMAD_SERF/${digitalocean_droplet.nomad_master.ipv4_address_private}:4648/g' /tmp/server.conf",
      "sudo mkdir /etc/nomad",
      "sudo mv /tmp/server.conf /etc/nomad/",
      "docker run -d --name nomad -v /var/run/docker.sock:/var/run/docker.sock -v /etc/nomad/server.conf:/etc/nomad/server.conf -p 4646:4646 -p 4647:4647 -p 4648:4648 shanesveller/nomad:0.2.2 agent -config /etc/nomad/server.conf"
    ]
  }
}

resource "digitalocean_ssh_key" "terraform" {
    name = "Terraform"
    public_key = "${file("terraform_rsa.pub")}"
}

resource "digitalocean_floating_ip" "nomad_master" {
  region = "nyc3"
  droplet_id = "${digitalocean_droplet.nomad_master.id}"
}

#resource "digitalocean_domain" "tenletters" {
#  name = "nomad.tenletters.org"
#  ip_address = "159.203.114.175"
#}

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
    private_key = "${file("terraform_rsa")}"
    timeout = "5m"
    agent = false
  }

  provisioner "file" {
    source = "client.conf"
    destination = "/tmp/client.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/NOMAD_MASTER_ADDR/${digitalocean_droplet.nomad_master.ipv4_address_private}:4647/g' /tmp/client.conf",
      "sudo mkdir /etc/nomad",
      "sudo mv /tmp/client.conf /etc/nomad/",
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