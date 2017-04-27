#!/bin/bash

set -e
cd `dirname $0`

function container_full_name() {
    # workaround for docker-compose ps: https://github.com/docker/compose/issues/1513
    echo `docker inspect -f '{{if .State.Running}}{{.Name}}{{end}}' \
            $(docker-compose ps -q) | cut -d/ -f2 | grep -E "_${1}_[0-9]"`
}

function dc_dockerfiles_images() {
    DOCKERDIRS=`grep -E '^\s*build:' docker-compose.yml|cut -d: -f2 |xargs`
    for dockerdir in $DOCKERDIRS; do
        echo `grep "^FROM " ${dockerdir}/Dockerfile |cut -d' ' -f2|xargs`
    done
}

function dc_exec_or_run() {
    CONTAINER_SHORT_NAME=$1
    CONTAINER_FULL_NAME=`container_full_name ${CONTAINER_SHORT_NAME}`
    shift
    if test -n "$CONTAINER_FULL_NAME" ; then
        # container already started
        docker exec -it $CONTAINER_FULL_NAME $*
    else
        # container not started
        docker-compose run --rm $CONTAINER_SHORT_NAME $*
    fi
}

case $1 in
    "")
        docker-compose up -d
        ;;
    init)
        test -e docker-compose.yml || cp docker-compose.yml.dist docker-compose.yml
        docker-compose run --rm wordpress_db chown -R mysql:mysql /var/lib/mysql
        docker-compose run --rm wordpress chown -R www-data:www-data /var/www/html
        ;;
    upgrade)
        read -rp "Êtes-vous sûr de vouloir effacer et mettre à jour les images et conteneurs Docker ? (o/n) "
        if [[ $REPLY =~ ^[oO]$ ]] ; then
            docker-compose pull
            for image in `dc_dockerfiles_images`; do
                docker pull $image
            done
            docker-compose build
            docker-compose stop
            docker-compose rm -f
            $0
        fi
        ;;
    prune)
        read -rp "Êtes-vous sûr de vouloir effacer les conteneurs et images Docker innutilisés ? (o/n)"
        if [[ $REPLY =~ ^[oO]$ ]] ; then
            # Note: la commande docker system prune n'est pas dispo sur les VPS OVH
            # http://stackoverflow.com/questions/32723111/how-to-remove-old-and-unused-docker-images/32723285
            exited_containers=$(docker ps -qa --no-trunc --filter "status=exited")
            test "$exited_containers" != ""  && docker rm $exited_containers
            dangling_images=$(docker images --filter "dangling=true" -q --no-trunc)
            test "$dangling_images" != "" && docker rmi $dangling_images
        fi
        ;;
    bash)
        dc_exec_or_run wordpress $*
        ;;
    mysql|mysqldump|mysqlrestore)
        case $1 in
            mysql)        cmd=mysql;     option="-it";;
            mysqldump)    cmd=mysqldump; option=     ;;
            mysqlrestore) cmd=mysql;     option="-i" ;;
        esac
        MYSQL_CONTAINER=`container_full_name wordpress_db`
        MYSQL_PASSWORD=`grep 'MYSQL_ROOT_PASSWORD:' docker-compose.yml|cut '-d:' -f2 |xargs`
        docker exec $option $MYSQL_CONTAINER $cmd --user=root --password="$MYSQL_PASSWORD" wordpress 
        ;;
    build|config|create|down|events|exec|kill|logs|pause|port|ps|pull|restart|rm|run|start|stop|unpause|up)
        docker-compose $*
        ;;
    *)
        cat <<HELP
Utilisation : $0 [COMMANDE]
  init         : initialise les données
               : lance les conteneurs
  upgrade      : met à jour les images et les conteneurs Docker
  prune        : efface les conteneurs et images Docker inutilisés
  bash         : lance bash sur le conteneur redmine
  mysql        : lance mysql sur le conteneur mysql, en mode interactif
  mysqldump    : lance mysqldump sur le conteneur mysql
  mysqlrestore : permet de rediriger un dump vers la commande mysql
  stop         : stoppe les conteneurs
  rm           : efface les conteneurs
  logs         : affiche les logs des conteneurs
HELP
        ;;
esac

