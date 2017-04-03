#!/bin/bash

WORKDIR=/test

docker run --rm -v $PWD:$WORKDIR -w $WORKDIR -e PERL5LIB=$WORKDIR/t/lib \
    docker.sdlocal.net/devel/stratperldancer bash -e -c '
        cpanm -q Minilla
        minil test --automated
'
