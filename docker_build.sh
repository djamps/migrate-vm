#!/bin/bash
docker build -t migratevm:temp .
docker create migratevm:temp
CONTAINER=$(docker ps -alq)
docker cp "$CONTAINER:/root/migratevm" .
docker container rm "$CONTAINER"
docker image rm migratevm:temp