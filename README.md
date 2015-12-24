# chouette-wordpress
==============

Le site internet wordpress pour le public

# Installation

First, clone this repository:

```bash
$ git clone git@github.com:lachouettecoop/chouette-wordpress.git
```

Create your instance of docker-compose.yml

```bash
$ cp docker-compose.yml.dist docker-compose.yml
```

With your favorite text editor edit 'docker-compose.yml' and do the following changes

* `MYSQL_ROOT_PASSWORD`: Change to a real password
* `VIRTUAL_HOST`: put your domain name here

Then, run:

```bash
$ docker-compose up -d
```

