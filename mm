#! /bin/bash

## Configurable session vars
#--------------------------------------

CANVAS_CONTAINER=example.com/canvas
HTTP_PORT=80
HTTPS_PORT=443

#--------------------------------------

canvas_dir=$(pwd)/canvas-lms
use_local_image=false

mm_docker() {
    echo "$@"
    docker "$@"
}


mm_help_build() {
    cat <<EOF
Usage: mm build IMAGE

IMAGE = web|db|cache|haproxy

EOF
}

mm_build() {
    case $1 in
        web)
            mm_docker build -t $CANVAS_CONTAINER:local mmooc-docker-canvas
            ;;
        db)
            mm_docker build -t mmooc/db:local mmooc-docker-postgresql
            ;;
        cache)
            mm_docker build -t mmooc/cache:local mmooc-docker-redis
            ;;
        dev)
            mm_docker build -t mmooc/dev:local mmooc-docker-dev
            ;;
        haproxy)
            mm_docker build -t mmooc/haproxy:local mmooc-docker-haproxy
            ;;
        *)
            mm_help build
            ;;
    esac
}

mm_url() {
  echo "Finding network ports for the container named 'web'"

  port_http=$(docker port web 80 | cut -d: -f2)
  port_https=$(docker port web 443 | cut -d: -f2)

  if which docker-machine >/dev/null 2>&1
  then
    echo "Found \"docker-machine\", guessing you're not on Linux. Getting ip address from VM."
    addr=$(docker-machine ip)
  else
    echo "No \"docker-machine\" found, guessing you're on Linux. Using localhost."
    addr="127.0.0.1"
  fi

  echo ""
  echo "Canvas addresses:"
  echo "  http://${addr}:${port_http}/"
  echo "  https://${addr}:${port_https}/"
}

mm_image_name() {
    if [ "$use_local_image" = true ]; then
        echo "$1:local"
    else
        echo $1
    fi
}

mm_container_name() {
    if [ "$use_local_image" = true ]; then
        echo "l$1"
    else
        echo $1
    fi
}

docker_run() {
    local container=$(mm_container_name $2)
    local image=$(mm_image_name $1)
    local options=$3

    if ! container_exists $container ; then
		# If web, use the user-defined ports
		if [ "$2" = "haproxy" ]; then
			local command="docker run --env-file=env -d -p $HTTP_PORT:$HTTP_PORT -p $HTTPS_PORT:$HTTPS_PORT $options --name=$container $image"
		else
			local command="docker run --env-file=env -d -P $options --name=$container $image"
		fi
		echo $command
		$command || true
    else
        docker start $container
    fi
}

docker_run_db() {
    docker_run mmooc/db db "--volumes-from=$(mm_container_name db-data)"
}

docker_run_cache() {
    docker_run mmooc/cache cache
}

docker_run_web() {
    docker_run $CANVAS_CONTAINER web "--volumes-from=$(mm_container_name web-data) --link $(mm_container_name db):db --link $(mm_container_name cache):cache"
}

docker_run_jobs() {
    local image=$(mm_image_name $CANVAS_CONTAINER)
    local command="docker run --env-file=env -d -P --volumes-from=$(mm_container_name web-data) --link=$(mm_container_name db):db --link=$(mm_container_name cache):cache --name=jobs $image /opt/canvas-lms/script/canvas_init run"
    echo $command
    $command || true
}

docker_run_haproxy() {
    docker_run mmooc/haproxy haproxy "--link $(mm_container_name web):web"
}

container_exists() {
    docker inspect "$1" > /dev/null 2>&1
}

mm_start_data() {
    if ! container_exists $(mm_container_name web-data) ; then
        docker run -v /var/log/apache2 -v /opt/canvas-lms/log -v /opt/canvas-lms/tmp/files --name=$(mm_container_name web-data) ubuntu:12.04
    fi

    if ! container_exists $(mm_container_name db-data) ; then
        docker run -v /var/lib/postgresql/9.1/main --name=$(mm_container_name db-data) ubuntu:12.04
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
        haproxy)
            docker_run_haproxy
            ;;
        *)
            mm_help start
            ;;
    esac
}

mm_init_schema() {
    local image=$(mm_image_name $CANVAS_CONTAINER)
    echo "Schema setup is bugged and needs to run twice."
    echo "Setting up schema for the first time. Output in init_schema.1.txt"
    docker run --rm --env-file=env -w /opt/canvas-lms --link=$(mm_container_name db):db --link=$(mm_container_name cache):cache $image bundle exec rake db:initial_setup >&2 2> init_schema.1.txt
    echo "Second time's the charm. Output in init_schema.2.txt"
    docker run --rm --env-file=env -w /opt/canvas-lms --link=$(mm_container_name db):db --link=$(mm_container_name cache):cache $image bundle exec rake db:initial_setup >&2 2> init_schema.2.txt
}


mm_initdb() {
    local image=$(mm_image_name mmooc/db)
    docker run --rm -t -i --env-file=env --user=root --volumes-from=$(mm_container_name db-data) $image /bin/bash /root/initdb
}


mm_boot() {
    mm_start_data
    mm_initdb
    mm_start db
    mm_start cache
    mm_init_schema
    mm_start web
    mm_start haproxy
    mm_url
}

mm_stop() {
    case $1 in
        services)
            for X in web cache db; do
                echo "Stopping & removing $X..."
                docker stop $X
                docker rm $X
            done
            ;;
        data)
            for X in db-data web-data; do
                echo "Stopping & removing $X..."
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
    reboot Stop & remove web, cache, db services, pull new images, restart.
    reset  Stop & remove web, cache, db services; remove web-data and db-data, pull new images, restart.
    start  Start one or all docker containers
    url    Print the url from which you can access canvas
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
        for X in db canvas cache haproxy tools dev; do
			## If canvas, use the custom canvas container
			if [ "$X" = "canvas" ]; then
				docker pull $CANVAS_CONTAINER
			else
				docker pull mmooc/$X
			fi
        done
        ;;
    rails)
        image=$(mm_image_name $CANVAS_CONTAINER)
        docker run --rm -t -i -P --env-file=env --link db:db -w /opt/canvas-lms $image bundle exec rails "$@"
        ;;
    rails-dev)
        docker run --rm -t -i -p 3000:3000 --env-file=env -e RAILS_ENV=development --link db:db --link cache:cache -w /opt/canvas-lms $CANVAS_CONTAINER bundle exec rails "$@"
        ;;
    dev)
        docker run -t -i -p 3001:3000 --name=$(mm_container_name dev) --env-file=env -e RAILS_ENV=development --link db:db --link cache:cache -w /opt/canvas-lms mmooc/dev
        ;;
    rake)
        docker run --rm -t -i -P --env-file=env -e RAILS_ENV=development -v $canvas_dir:/canvas-lms --link db:db -w /canvas-lms $CANVAS_CONTAINER bundle exec rake "$@"
        ;;
    reboot)
        mm_stop services
        for X in db canvas cache; do
			## If canvas, use the custom canvas container
			if [ "$X" = "canvas" ]; then
				docker pull $CANVAS_CONTAINER
			else
				docker pull mmooc/$X
			fi
        done
        mm_boot
        ;;
    reset)
        mm_stop services
        mm_stop data
        for X in db canvas cache; do
			## If canvas, use the custom canvas container
			if [ "$X" = "canvas" ]; then
				docker pull $CANVAS_CONTAINER
			else
				docker pull mmooc/$X
			fi
        done
        mm_boot
        ;;
    start)
        mm_start "$@"
        ;;
    stop)
        mm_stop "$@"
        ;;
    url)
        mm_url
        ;;
    *)
        mm_help
        ;;
esac
