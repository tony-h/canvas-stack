#! /bin/bash

set -e

canvas_dir=$(pwd)/canvas-lms
use_local_image=false

mm_docker() {
    echo "$@"
    docker "$@"
}


mm_help_build() {
    cat <<EOF
Usage: mm build IMAGE

IMAGE = web|db|cache|ha_proxy

EOF
}

mm_build() {
    case $1 in
        web)
            mm_docker build -t mmooc/canvas:local mmooc-docker-canvas
            ;;
        db)
            mm_docker build -t mmooc/db:local mmooc-docker-postgresql
            ;;
        cache)
            mm_docker build -t mmooc/cache:local mmooc-docker-redis
            ;;
        haproxy)
            mm_docker build -t mmooc/haproxy:local mmooc-docker-haproxy
            ;;
        *)
            mm_help build
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

    local command="docker run --env-file=env -d -P $options --name=$container $image"
    echo $command
    $command || true
}

docker_run_db() {
    docker_run mmooc/db db "--volumes-from=db-data"
}

docker_run_cache() {
    docker_run mmooc/cache cache
}

docker_run_web() {
    docker_run mmooc/canvas web "--volumes-from=web-data --link db:db --link cache:cache"
}

docker_run_jobs() {
    local image=$(mm_image_name mmooc/canvas)
    local command="docker run --env-file=env -d -P --volumes-from=web-data --link=db:db --link=cache:cache --name=jobs $image /opt/canvas-lms/script/canvas_init run"
    echo $command
    $command || true
}

docker_run_haproxy() {
    docker_run mmooc/canvas haproxy "--link web:web"
}

container_exists() {
    docker inspect "$1" > /dev/null 2>&1
}

mm_start_data() {
    if ! container_exists web-data ; then
        docker_run ubuntu:12.04 web-data "-v /var/log/apache2 -v /opt/canvas-lms/log -v /opt/canvas-lms/tmp/files"
    fi

    if ! container_exists db-data ; then
        docker_run ubuntu:12.04 db-data "-v /var/lib/postgresql/9.1/main"
    fi
}

mm_help_start() {
    cat <<EOF
Usage: mm start COMMAND

Commands
    all     Start all service containers
    cache   Start the Redis container
    data    Start data volume containers
    db      Start the PostgreSQL container
    jobs    FIXME
    web     Start the Canvas container
    haproxy Start the HAProxy container
EOF
}

mm_start() {
    case $1 in
        all)
            docker_run_db
            docker_run_cache
            docker_run_web
            docker_run_haproxy
            docker_run_jobs
            ;;
        data)
            mm_start_data
            ;;
        db)
            docker_run_db
            ;;
        cache)
            docker_run_cache
            ;;
        jobs)
            docker_run_jobs
            ;;
        web)
            docker_run_web
            ;;
        hapoxy)
            docker_run_web
            ;;
        *)
            mm_help start
            ;;
    esac
}

mm_init_schema() {
    local image=$(mm_image_name mmooc/canvas)
    docker run --rm --env-file=env -w /opt/canvas-lms --link=db:db --link=cache:cache $image bundle exec rake db:initial_setup
}


mm_initdb() {
    local image=$(mm_image_name mmooc/db)
    docker run --rm -t -i --env-file=env --user=root --volumes-from=db-data $image /bin/bash /root/initdb
}


mm_boot() {
    mm_start_data
    mm_initdb
    mm_start db
    mm_start cache
    mm_init_schema
    mm_start web
    mm_start jobs
}

mm_stop() {
    case $1 in
        all)
            for X in web haproxy cache db; do
                echo "Stopping $X..."
                docker stop $X
                docker rm $X
            done
            ;;
        *)
            mm_help stop
            ;;
    esac
}

mm_help_main() {
    cat <<EOF
Usage: mm [OPTIONS] COMMAND

Utilities FIXME

Options
    -l, --local  Use images with tag :local

Commads:
    boot   First time use. Takes up the whole system
    build  Build local docker images
    help   Display help information
    initdb Create the postgres cluster, roles and databases
    init-schema Initialize the database schema and insert initial data
    pull   Pull new versions of docker images
    rails  FIXME
    rake   FIXME
    start  Start one or all docker containers
EOF
}

mm_help_fixme() {
    echo "FIXME To be documented ..."
}

mm_help() {
    case $1 in
        build)
            mm_help_build
            ;;
        boot)
            mm_help_fixme
            ;;
        help)
            mm_help_fixme
            ;;
        initdb)
            mm_help_fixme
            ;;
        init-schema)
            mm_help_fixme
            ;;
        pull)
            mm_help_fixme
            ;;
        rails)
            mm_help_fixme
            ;;
        rails-dev)
            mm_help_fixme
            ;;
        rake)
            mm_help_fixme
            ;;
        start)
            mm_help_start
            ;;
        stop)
            mm_help_fixme
            ;;
        *)
            mm_help_main
            ;;
    esac
}

if [ "$1" = "--local" -o "$1" = "-l" ]; then
    use_local_image=true
    shift
fi
command=$1
shift || true
case $command in
    build)
        mm_build "$@"
        ;;
    boot)
        mm_boot
        ;;
    help)
        mm_help "$@"
        ;;
    initdb)
        mm_initdb
        ;;
    init-schema)
        mm_init_schema
        ;;
    pull)
        for X in db canvas cache haproxy tools; do
            docker pull mmooc/$X
        done
        ;;
    rails)
        image=$(mm_image_name mmooc/canvas)
        docker run --rm -t -i -P --env-file=env --link db:db -w /opt/canvas-lms $image bundle exec rails "$@"
        ;;
    rails-dev)
        docker run --rm -t -i -p 3000:3000 --env-file=env -e RAILS_ENV=development --link db:db --link cache:cache -w /opt/canvas-lms mmooc/canvas bundle exec rails "$@"
        ;;
    dev)
        docker run -t -i -p 3000:3000 --name=dev --env-file=env -e RAILS_ENV=development --link db:db --link cache:cache -w /opt/canvas-lms mmooc/canvas /bin/bash
        ;;
    rake)
        docker run --rm -t -i -P --env-file=env -e RAILS_ENV=development -v $canvas_dir:/canvas-lms --link db:db -w /canvas-lms mmooc/canvas bundle exec rake "$@"
        ;;
    start)
        mm_start "$@"
        ;;
    stop)
        mm_stop "$@"
        ;;
    *)
        mm_help
        ;;
esac
