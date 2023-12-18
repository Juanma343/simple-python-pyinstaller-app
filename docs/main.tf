terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {
  host    = "npipe:////.//pipe//docker_engine"
}

resource "docker_network" "my_network" {
  name   = "my_network"
}

resource "docker_volume" "certs" {
  name = "certs"
}

resource "docker_volume" "data" {
  name = "data"
}



resource "docker_container" "jenkins" {
  name  = "jenkins"
  image = "juanma343/myjenkins-blueocean:2.426.2-1"
  privileged = true

  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_TLS_VERIFY=1",
    "DOCKER_CERT_PATH=/certs/client",
    "JAVA_OPTS=-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true",
  ]

  ports {
    internal = 8080
    external = 8081
  }
  networks_advanced {
    name = docker_network.my_network.name
    aliases = ["docker"]
  }
  volumes{
    volume_name = docker_volume.data.name
    container_path = "/var/jenkins_home"
  }
  volumes{
    volume_name = docker_volume.certs.name
    container_path = "/certs/client"
  }
}

resource "docker_container" "dind" {
  name  = "dind"
  image = "docker:dind"
  restart = "no"
  privileged = true
  networks_advanced {
    name = docker_network.my_network.name
    aliases = ["docker"]
  }

  env = [
    "DOCKER_TLS_CERTDIR=/certs",
  ]

  ports {
    internal = 3000
    external = 3000
  }
  ports {
    internal = 2376
    external = 2376
  }
  ports {
    internal = 5000
    external = 5000
  }

  volumes{
    volume_name = docker_volume.data.name
    container_path = "/var/jenkins_home"
  }
  volumes{
    volume_name = docker_volume.certs.name
    container_path = "/certs/client"
  }
}