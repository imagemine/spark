#!/usr/bin/env bash
set -e
source build.properties

for v in $(echo $version|sed s/","/" "/g);
do 
  ./spark-builder.sh ${v}
  docker push ${owner}/${artifact}:${v}
done;


