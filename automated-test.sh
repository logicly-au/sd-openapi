#!/bin/bash

WORKDIR=/test

docker-compose build --pull
docker-compose run --rm sd-openapi minil test --automated
