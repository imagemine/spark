#!/usr/bin/env bash

set -e
version=$1

REPO_BASE=docker.io
REPO_OWNER=skhatri
REPO=${REPO_BASE}/${REPO_OWNER}
WORKDIR=$(pwd)/build

if [[ -z ${version} ]]; then
  echo "spark version is required. eg 3.1.1 or 3.1.2"
  exit 1;
fi;

if [[ ! -d ${WORKDIR} ]]; then
  mkdir ${WORKDIR}
fi;
 
SPARK_HOME=${WORKDIR}/spark-${version}-bin-hadoop3.2
bin_file="spark-${version}-bin-hadoop3.2.tgz"

fetch() {
  if [[ -f ${WORKDIR}/${bin_file} ]];then
    echo "not downloading binary as it exists"
    return;
  fi;
  local url="https://apache.mirror.digitalpacific.com.au/spark/spark-${version}/${bin_file}"

  curl -sL -o ${WORKDIR}/${bin_file} ${url}
  if [[ $? -ne 0 ]]; then
    echo spark download failed.
    exit 1;
  fi;
}

extra_libs() {
  curl -sL -o ${SPARK_HOME}/jars/delta-core_2.12-1.0.0.jar https://repo1.maven.org/maven2/io/delta/delta-core_2.12/1.0.0/delta-core_2.12-1.0.0.jar
}

fetch

tar zxf ${WORKDIR}/${bin_file} -C ${WORKDIR}

if [[ ! -d ${SPARK_HOME} ]]; then
  echo "spark home ${SPARK_HOME} expected. it is not present."
  exit 1;
fi;

extra_libs

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

${SPARK_HOME}/bin/docker-image-tool.sh -n -r ${REPO} -t ${SPARK_VERSION} ${BUILD_PARAMS} -p ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile build









