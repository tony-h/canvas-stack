#! /bin/bash

set -e
set -x

canvas_dir=$(pwd)/canvas-lms
use_local_image=false 

mm_build() {
    case $1 in
        web)
            docker build -t mmooc/web:local mmooc-docker-canvas
            ;;
        db)
            docker build -t mmooc/db:local mmooc-docker-postgresql
            ;;
        cache)
            docker build -t mmooc/cache:local mmooc-docker-redis
            ;;
        haproxy)
            docker build -t mmooc/haproxy:local mmooc-docker-haproxy
            ;;
        *)
            echo FIXME
            ;;
    esac
}

mm_image_name() {
    if [ "$use_local_image" = true ]; then
        echo "$1:local"
    else
        echo $1
    fi 
}

docker_run() {
    local container=$2
    local image=$(mm_image_name $1)
    local options=$3

    if [ "$use_local_image" = true ]; then
        image="$image:local"
    fi

    docker run --env-file=env -d -P $options --name=$container $image
}

docker_run_db() {
    docker_run mmooc/db db "--volumes-from=db-data"
}

docker_run_cache() {
    docker_run mmooc/cache cache
}

docker_run_web() {
    docker_run mmooc/canvas web "--volumes-from=web-data --link db:db"
}

docker_run_haproxy() {
    docker_run mmooc/canvas haproxy "--link web:web"
}

container_exists() {
    docker inspect "$1" > /dev/null 2>&1 
}

mm_start_data() {
    if ! container_exists web-data ; then 
        docker_run ubuntu:12.04 web-data "-v /var/log/apache2 -v /opt/canvas-lms/log"
    fi
    
    if ! container_exists db-data ; then 
        docker_run ubuntu:12.04 db-data "-v /var/lib/postgresql/9.1/main"
    fi
}

mm_start() {
    case $1 in
        "all")
            docker_run_db
            docker_run_cache
            docker_run_web
            docker_run_haproxy
            ;;
        "data")
            mm_start_data
            ;;
        "db")
            docker_run_db
            ;;
        "cache")
            docker_run_cache
            ;;
        "web")
            docker_run_web
            ;;
        "hapoxy")
            docker_run_web
            ;;
        *)
            cat <<EOF
Usage: mm start COMMAND

Commands
    all     FIXME
    db      FIXME
    cache   FIXME
    web     FIXME
    haproxy FIXME
EOF
            ;;
    esac
}

mm_boot() {
    mm_start_data
    #FIXME initdb
    mm_start all
}

mm_stop() {
    case $1 in
        "all")
            for X in web haproxy cache db; do
                echo "Stopping $X..."
                docker stop $X
                docker rm $X
            done
            ;;
        "*")
            echo "FIXME"
            ;;
    esac
}

if [ "$1" = "--local" -o "$1" = "-l" ]; then
    use_local_image=true
    shift
fi
command=$1
shift
case $command in
    build)
        mm_build "$@"
        ;;
    boot)
        mm_boot
        ;;
    initdb)
        image=$(mm_image_name mmooc/db)
        docker run --rm -t -i --env-file=env --user=root --volumes-from=db-data $image /bin/bash # /root/initdb
        ;;
    rails)
        docker run --rm -t -i -P -e RAILS_ENV=development -v $canvas_dir:/canvas-lms --link db:db -w /canvas-lms mmooc/canvas bundle exec rails $@
        ;;
    rake)
        docker run --rm -t -i -P -e RAILS_ENV=development -v $canvas_dir:/canvas-lms --link db:db -w /canvas-lms mmooc/canvas bundle exec rake $@
        ;;
    start)
        mm_start "$@"
        ;;
    stop)
        mm_stop "$@"
        ;;
    *)
        cat <<EOF
Usage: mm [OPTIONS] COMMAND

Utilities FIXME

Options
    --local -l  Use images with tag :local

Commads:
    build  FIXME
    initdb FIXME
    rails  FIXME
    rake   FIXME
    start  FIXME
EOF
        ;;
esac
