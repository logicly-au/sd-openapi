#!/bin/bash

IMAGE=docker.sdlocal.net/devel/stratperlbase
WORKDIR=/test

# This automated test just uses cpanm to attempt to install the module into
# the stratperlbase image.
# I originally used the stratperldancer image, but that now has this module
# installed, which makes the testing a bit less clean room.

docker pull $IMAGE
docker run --rm -t -v $PWD:$WORKDIR:ro $IMAGE bash -c "
    # Copy the local dir into temp as we've got in mounted read-only, and
    # cpanm doesn't like that for reasons unknown.
    cp -a $WORKDIR /tmp/
    cd /tmp$WORKDIR
    echo Installing dependencies
    cpanm --installdeps -q .
    echo Installing SD-OpenAPI
    cpanm -v .
"
