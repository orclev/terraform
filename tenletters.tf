variable "do_token" {}
variable "atlas_token" {}
variable "ssh_fingerprint" {}
variable "ssh_private" {}

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
  ssh_keys = [1525856,"${var.ssh_fingerprint}"]
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

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/NOMAD_RPC/${digitalocean_droplet.nomad_master.ipv4_address_private}:4647/g' /tmp/server.conf",
      "sudo sed -i 's/NOMAD_HTTP/${digitalocean_droplet.nomad_master.ipv4_address}:4646/g' /tmp/server.conf",
      "sudo sed -i 's/NOMAD_SERF/${digitalocean_droplet.nomad_master.ipv4_address_private}:4648/g' /tmp/server.conf",
      "sudo sed -i 's/ATLAS_TOKEN/${var.atlas_token}/g' /tmp/server.conf",
      "sudo mkdir /etc/nomad",
      "sudo mv /tmp/server.conf /etc/nomad/",
      "docker run -name consul voxxit/consul agent -atlas orclev/digitalocean -atlas-join -atlas-token ${var.atlas_token} -bootstrap-expect 1 -server -advertise ${digitalocean_droplet.nomad_master.ipv4_address_private} -data-dir /srv/consul",
      "docker run -d --name nomad -v /var/run/docker.sock:/var/run/docker.sock -v /etc/nomad/server.conf:/etc/nomad/server.conf -p 4646:4646 -p 4647:4647 -p 4648:4648 shanesveller/nomad:0.2.2 agent -config /etc/nomad/server.conf"
    ]
  }
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
  ssh_keys = [1525856,"${var.ssh_fingerprint}"]
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
      "docker run -d --name consul voxxit/consul agent -atlas orclev/digitalocean -atlas-join -atlas-token ${var.atlas_token} -join ${digitalocean_droplet.nomad_master.ipv4_address_private} -data-dir /srv/consul",
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
