#! /bin/bash

canvas_dir=$(pwd)/canvas-lms

command=$1
shift
case $command in
    rake)
        docker run --rm -t -i -P -e RAILS_ENV=development -v $canvas_dir:/canvas-lms --link db:db -w /canvas-lms mmooc/canvas bundle exec rake $@
        ;;
    rails)
        docker run --rm -t -i -P -e RAILS_ENV=development -v $canvas_dir:/canvas-lms --link db:db -w /canvas-lms mmooc/canvas bundle exec rails $@
        ;;
    *)
        cat <<EOF
Usage: mm COMMAND

Utilities FIXME

Commads:
rake - FIXME
rails - FIXME

EOF
        ;;
esac
