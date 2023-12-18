# Entregable 3 - Terraform + SCV + Jenkins
Gonzalo Barba Rodríguez - Juan Manuel Grondona Nuño

## Introducción
En este entregable sobre 'Terraform + SCV + Jenkins', ejecutaremos una aplicación Python mediante Jenkins en un contenedor Docker para realizar pruebas sobre esta.

## Personalización de imagen

Lo primero que vamos a hacer es la personalización de la imagen Docker de Jenkins estándar para poder instalar unos plugins además de definir adecuadamente unas variables de entorno. Esto lo lograremos creando un Dockerfile, que es el siguiente:
```dockerfile
FROM jenkins/jenkins:2.426.1-jdk17
USER root
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
  https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean:1.27.9 docker-workflow:572.v950f58993843"
```
Tras esto, solo tenemos que construir la imagen y subirla con estos comandos:
```shell
docker build -t myjenkins-blueocean:2.426.2-1 .
docker tag myjenkins-blueocean:2.426.2-1 juanma343/myjenkins-blueocean:2.426.2-1
docker push juanma343/myjenkins-blueocean:2.426.2-1
```

## Creación con Terraform

Terraform es una herramienta que nos permite la administración de contenedores, volúmenes y redes de Docker. En este caso, hemos configurado un archivo de Terraform para llevar a cabo esta práctica. El archivo `main.tf` se compone de las siguientes partes.

En la primera parte, se especifica que se requiere el proveedor de Terraform para Docker de la versión 3.0.1.
```hcl
terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }         
}
```

A continuación, se configura el proveedor Docker para que se comunique con el daemon de Docker utilizando un socket de Windows.
```hcl
provider "docker" {
  host    = "npipe:////.//pipe//docker_engine"
}
```

Después, se crean una red Docker llamada "my_network" y dos volúmenes Docker llamados "certs" y "data".
```hcl
resource "docker_network" "my_network" {
  name   = "my_network"
}

resource "docker_volume" "certs" {
  name = "certs"
}

resource "docker_volume" "data" {
  name = "data"
}
```

Por último, se crean los contenedores. El primero es un contenedor llamado "jenkins" que utiliza la imagen "juanma343/myjenkins-blueocean:2.426.2-1" que creamos en los pasos previos. Aspectos a destacar de este contenedor son los puertos, utilizando el 8081 en el externo debido a problemas de compatibilidad con otros programas del ordenador. Además, se asignan volúmenes y se conecta a una red que se definió anteriormente. Por último, se menciona la asignación de variables de entorno relacionadas con Docker.
```hcl
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
```

Para el segundo contenedor, se describe el contenedor Docker-in-Docker (DinD). Similar al contenedor Jenkins, tiene configuraciones para la red, volúmenes y privilegios iguales al contenedor anterior, permitiendo la comunicación entre ellos, además de los puertos necesarios para su funcionamiento.
```hcl
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
```

Una vez que tengas este archivo, solo necesitarás ejecutar los siguientes comandos para la creación de los contenedores de Docker.
```shell
terraform init
terraform apply
```

## Configuración inicial de Jenkins

Después de acceder al puerto 8081 del host local en el navegador, se mostrará una página que solicitará una contraseña. Para continuar, solo es necesario revisar el log del contenedor llamado jenkins para acceder a la contraseña y simplemente introducirla.

Para finalizar, solo necesitarás proporcionar los datos para el usuario administrador y solamente tendrás que iniciar sesión cada vez que accedas.

## Creación del job

Para crear el job que ejecutará Jenkins, primero es necesario saber qué vamos a ejecutar. En este caso, es el repositorio de GitHub llamado [simple-python-pyinstaller-app](https://github.com/jenkins-docs/simple-python-pyinstaller-app) al que haremos un Fork, el cual utilizaremos en Jenkins.

Lo segundo que tenemos que hacer es subir al fork el siguiente archivo de Jenkins.
```groovy
pipeline {
    agent none


    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            agent {
                docker {
                    image 'python:3.12.1-alpine3.19'
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            agent {
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') { 
            agent any
            environment { 
                VOLUME = '$(pwd)/sources:/src'
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) { 
                    unstash(name: 'compiled-results') 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'" 
                }
            }
            post {
                success {
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals" 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
}
```

Tras crear este archivo, lo colocamos en la raíz de nuestro fork. Luego, solo nos queda crear y ejecutar el job en Jenkins.

Por último, en la página de inicio de Jenkins, aparecerá un botón que dice "Create new job". Tras presionarlo, te dirigirá a una pantalla donde te pedirá un nombre y elegir una de las opciones. Simplemente coloca el nombre deseado y elige la opción de "Pipeline".

Después de eso, aparecerá la configuración de este job. En este caso, solo tendrás que dirigirte a la sección de Pipeline, y en la parte de definición, elegir la opción "Pipeline script from SCM". Posteriormente, en SCM, elige la opción de Git, y usa la URL del fork que creaste anteriormente. Tras guardar, habrás creado el job correctamente.

Después de esto, solo queda la ejecución del job con el plugin de Blue Ocean, que se encuentra en la pestaña de inicio. Después de todo esto, solo hay que presionar "Run" y luego "Open" para ver la progresión de los stages.