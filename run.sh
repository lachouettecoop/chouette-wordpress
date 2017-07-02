#!/bin/bash

set -e
cd `dirname $0`

function container_full_name() {
    # Retourne le nom complet du coneneur $1 si il est en cours d'exécution
    # workaround for docker-compose ps: https://github.com/docker/compose/issues/1513
    ids=$(docker-compose ps -q)
    if [ "$ids" != "" ] ; then
        echo `docker inspect -f '{{if .State.Running}}{{.Name}}{{end}}' $ids \
              | cut -d/ -f2 | grep -E "_${1}_[0-9]"`
    fi
}

function dc_dockerfiles_images() {
    # Retourne la liste d'images Docker depuis les Dockerfile build listés dans docker-compose.yml
    local DOCKERDIRS=`grep -E '^\s*build:' docker-compose.yml|cut -d: -f2 |xargs`
    local dockerdir
    for dockerdir in $DOCKERDIRS; do
        echo `grep "^FROM " ${dockerdir}/Dockerfile |cut -d' ' -f2|xargs`
    done
}

function dc_exec_or_run() {
    # Lance la commande $2 dans le container $1, avec 'exec' ou 'run' selon si le conteneur est déjà lancé ou non
    local options=
    while [[ "$1" == -* ]] ; do
        options="$options $1"
        shift
    done
    local CONTAINER_SHORT_NAME=$1
    local CONTAINER_FULL_NAME=`container_full_name ${CONTAINER_SHORT_NAME}`
    shift
    if test -n "$CONTAINER_FULL_NAME" ; then
        # container already started
        docker exec -it $options $CONTAINER_FULL_NAME "$@"
    else
        # container not started
        docker-compose run --rm $options $CONTAINER_SHORT_NAME "$@"
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
        dc_exec_or_run wordpress "$@"
        ;;

    mysql|mysqldump)
        cmd=$1
        shift
        if [ "$cmd" = "mysql" ] ; then
            # check if input file descriptor (0) is a terminal
            if [ -t 0 ] ; then
                option="-it";
            else
                option="-i";
            fi
        else
            option="";
        fi
        MYSQL_CONTAINER=`container_full_name wordpress_db`
        MYSQL_PASSWORD=`grep 'MYSQL_ROOT_PASSWORD:' docker-compose.yml|cut '-d:' -f2 |xargs`
        if [ "$MYSQL_CONTAINER" = "" ] ; then
            echo "Démare le conteneur wordpress_db" > /dev/stderr
            docker-compose up -d wordpress_db > /dev/stderr
            sleep 3
            MYSQL_CONTAINER=`container_full_name wordpress_db`
        fi
        echo docker exec $option $MYSQL_CONTAINER $cmd --user=root --password="$MYSQL_PASSWORD" wordpress "$@"
        docker exec $option $MYSQL_CONTAINER $cmd --user=root --password="$MYSQL_PASSWORD" wordpress "$@"
        ;;

    dumpall)
        shift
        MYSQL_CONTAINER=`container_full_name wordpress_db`
        MYSQL_PASSWORD=`grep 'MYSQL_ROOT_PASSWORD:' docker-compose.yml|cut '-d:' -f2 |xargs`
        docker exec $MYSQL_CONTAINER mysqldump --user=root --password="$MYSQL_PASSWORD" --all-databases --events "$@"
        ;;

    restoreall)
        shift
        MYSQL_CONTAINER=`container_full_name wordpress_db`
        MYSQL_PASSWORD=`grep 'MYSQL_ROOT_PASSWORD:' docker-compose.yml|cut '-d:' -f2 |xargs`
        docker exec -i $MYSQL_CONTAINER mysql --user=root --password="$MYSQL_PASSWORD" "$@"
        ;;

    build|config|create|down|events|exec|kill|logs|pause|port|ps|pull|restart|rm|run|start|stop|unpause|up)
        docker-compose "$@"
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
  dumpall      : lance mysqldump --all-databases --events
  restoreall   : permet de restaure le contenu d'un dumpall
  stop         : stoppe les conteneurs
  rm           : efface les conteneurs
  logs         : affiche les logs des conteneurs
HELP
        ;;
esac

