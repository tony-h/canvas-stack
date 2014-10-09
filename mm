#! /bin/bash

set -e

canvas_dir=$(pwd)/canvas-lms

mm_build() {
    case $1 in
        haproxy)
            docker build -t mmooc/haproxy:test mmooc-docker-haproxy
            ;;
        *)
            echo FIXME
            ;;
    esac
}

docker_run() {
    if container_exists $2; then
      docker start $2
    else
      docker run --env-file=env -d -P $3 --name=$2 $1
    fi
}

docker_run_db() {
    docker_run mmooc/db db # "--volumes-from=db-data"
}

docker_run_cache() {
    docker_run mmooc/cache cache
}

docker_run_web() {
    docker_run mmooc/canvas web "--volumes-from=web-data --link db:db"
}

container_exists() {
    docker inspect $1 2>&1 >/dev/null
}

mm_start() {
    if ! container_exists web-data ; then 
        docker_run ubuntu:12.04 web-data "-v /var/log/apache2 -v /opt/canvas-lms/log"
    fi
    
    if ! container_exists db-data ; then 
        docker_run ubuntu:12.04 db-data "-v /var/lib/postgresql/9.1/main"
    fi
    
    case $1 in
        "all")
            docker_run_db
            docker_run_cache
            docker_run_web
            docker_run_haproxy
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
        *)
            echo FIXME
            ;;
    esac
}

command=$1
shift
case $command in
    build)
        mm_build "$@"
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
    *)
        cat <<EOF
Usage: mm COMMAND

Utilities FIXME

Commads:
    build FIXME    
    rails FIXME
    rake  FIXME
    start FIXME
EOF
        ;;
esac
