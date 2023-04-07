#!/usr/bin/env bash

set -e
version=$1

REPO_BASE=docker.io
REPO_OWNER=cloudnativek8s
REPO=${REPO_BASE}/${REPO_OWNER}
WORKDIR=$(pwd)/build

if [[ -z ${version} ]]; then
  echo "spark version is required. eg 3.2.3 or 3.3.2"
  exit 1;
fi;

if [[ ! -d ${WORKDIR} ]]; then
  mkdir ${WORKDIR}
fi;

hadoop_minor=""

if [[ $version =~ ^3.2.*$ ]];
then 
  hadoop_minor=".2"
else
  build_file="Dockerfile"
fi; 

SPARK_HOME=${WORKDIR}/spark-${version}-bin-hadoop3${hadoop_minor}

bin_file="spark-${version}-bin-hadoop3${hadoop_minor}.tgz"

fetch() {
  if [[ -f ${WORKDIR}/${bin_file} ]];then
    echo "not downloading binary as it exists"
    return;
  fi;
  local url="https://archive.apache.org/dist/spark/spark-${version}/${bin_file}"
  echo ${url}
  curl -sL -o ${WORKDIR}/${bin_file} ${url}
  if [[ $? -ne 0 ]]; then
    echo spark download failed.
    exit 1;
  fi;
}

extra_libs() {
  local ver=$1
  local lib_file="extra/default.properties"
  if [[ -f "extra/${ver}.properties" ]];
  then
    lib_file="extra/${ver}.properties"
  fi;
  for line in $(cat ${lib_file});
  do
    fname=$(basename $line)
    curl -sL -o ${SPARK_HOME}/jars/${fname} ${line}
  done;
}

fetch

tar zxf ${WORKDIR}/${bin_file} -C ${WORKDIR}

if [[ ! -d ${SPARK_HOME} ]]; then
  echo "spark home ${SPARK_HOME} expected. it is not present."
  exit 1;
fi;

extra_libs ${version}

export SPARK_VERSION=${version}

cat $SPARK_HOME/kubernetes/dockerfiles/spark/Dockerfile | sed "s/FROM openjdk/FROM ${REPO_BASE}\/openjdk/" > ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile_tmp

echo 'USER root
ARG spark_name=app
RUN mkdir /opt/app
RUN groupadd --system --gid=${spark_uid} ${spark_name}
RUN useradd --system --no-log-init --gid ${spark_name} --uid=${spark_uid} ${spark_name}
RUN chown -R ${spark_name}:${spark_name} /opt/spark /opt/app
USER ${spark_name}
' >> ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile_tmp

mv ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile_tmp ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile
export SPARK_UID=999
BUILD_PARAMS="-b spark_uid=999 -b spark_name=app -b java_image_tag=11-jre-slim"


clean_unused_files() {
  local target=$1
  local n=0
  local cleaned=0
  for jf in $(ls $target);
  do
    cleaned=0
    for pom in $(jar tvf $target/$jf|grep -E "pom.(xml|properties)$"|awk -F" " '{print $8}');
    do
      zip -d $target/$jf $pom
      cleaned=1
    done;
    if [[ $cleaned -eq 1 ]];
    then
      mv $target/$jf $target/lib-$n.jar
    fi;
    n=$((n+1))
  done;
}

clean_unused_files $SPARK_HOME/jars
if [[ -z $build_file ]];
then
${SPARK_HOME}/bin/docker-image-tool.sh -n -r ${REPO} -t ${SPARK_VERSION} ${BUILD_PARAMS} -p ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile build
else
  docker build --no-cache -t ${REPO}/spark:${SPARK_VERSION} ${SPARK_HOME} -f ${build_file}
fi;




