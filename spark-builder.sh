#!/usr/bin/env bash

set -e
source build.properties
version=$1
mode=$2
image_tag=$3
sub=$4

REPO_BASE=docker.io
REPO_OWNER=cloudnativek8s
REPO=${REPO_BASE}/${REPO_OWNER}
WORKDIR=$(pwd)/build
PLATFORMS="linux/amd64,linux/arm64"

if [[ -z ${version} ]]; then
  echo "spark version is required. eg 3.2.3 or 3.3.2"
  exit 1
fi

if [[ ! -d ${WORKDIR} ]]; then
  mkdir ${WORKDIR}
fi

hadoop_minor=""

if [[ $version =~ ^3.2.*$ ]]; then
  hadoop_minor=".2"
else
  build_file="Dockerfile"
fi

SPARK_HOME=${WORKDIR}/spark-${version}-bin-hadoop3${hadoop_minor}

bin_file="spark-${version}-bin-hadoop3${hadoop_minor}.tgz"

fetch() {
  if [[ -f ${WORKDIR}/${bin_file} ]]; then
    echo "not downloading binary as it exists"
    if [[ -d ${WORKDIR}/spark-${version}-bin-hadoop3${hadoop_minor} ]]; then
      echo removing existing directory ${WORKDIR}/spark-${version}-bin-hadoop3${hadoop_minor}
      rm -rf ${WORKDIR}/spark-${version}-bin-hadoop3${hadoop_minor}
    fi
    return
  fi
  local spark_host="https://dlcdn.apache.org/spark"
  local url="${spark_host}/spark-${version}/${bin_file}"
  echo ${url}
  curl -L -o ${WORKDIR}/${bin_file} ${url}
  if [[ $? -ne 0 ]]; then
    echo spark download failed.
    exit 1
  fi
}

extra_libs() {
  local ver=$1
  local target=$2
  local tag=$3
  local lib_file="extra/default.properties"
  if [[ -f "extra/${ver}/${tag}" ]]; then
    lib_file="extra/${ver}/${tag}"
  fi
  for line in $(cat ${lib_file}); do
    fname=$(basename $line)
    patt="^"$(echo $fname | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+/[0-9]+\.[0-9]+\.[0-9]+/g")"$"
    set +e
    matching_file=$(ls $target | grep -E $patt | head -1)
    if [[ $matching_file != "" ]]; then
      echo removing old version ${matching_file} and replacing with ${fname}
      rm $target/$matching_file
    fi
    set -e
    curl -sL -o ${target}/${fname} ${line}
  done
}

fetch

tar zxf ${WORKDIR}/${bin_file} -C ${WORKDIR} >/dev/null 2>&1

if [[ ! -d ${SPARK_HOME} ]]; then
  echo "spark home ${SPARK_HOME} expected. it is not present."
  exit 1
fi

extra_libs ${version} ${SPARK_HOME}/jars ${sub}

export SPARK_VERSION=${version}

cat $SPARK_HOME/kubernetes/dockerfiles/spark/Dockerfile | sed "s/FROM openjdk/FROM ${REPO_BASE}\/openjdk/" >${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile_tmp

echo 'USER root
ARG spark_name=app
RUN mkdir /opt/app
RUN groupadd --system --gid=${spark_uid} ${spark_name}
RUN useradd --system --no-log-init --gid ${spark_name} --uid=${spark_uid} ${spark_name}
RUN chown -R ${spark_name}:${spark_name} /opt/spark /opt/app
USER ${spark_name}
' >>${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile_tmp

mv ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile_tmp ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile
export SPARK_UID=999
BUILD_PARAMS="-b spark_uid=999 -b spark_name=app -b java_image_tag=11-jre-slim"

clean_unused_files() {
  local target=$1
  local resname=$2
  local filter=$3
  if [[ "$resname" == "" ]]; then
    resname="pom.(xml|properties)$"
  fi
  local n=0
  local cleaned=0
  for jf in $(ls $target); do
    echo $jf $filter
    if [[ "$filter" == "" ]] || [[ $jf =~ $filter ]]; then
      cleaned=0
      for pom in $(jar tvf $target/$jf | grep -E ${resname} | awk -F" " '{print $8}'); do
        zip -q -d $target/$jf $pom
        cleaned=1
      done
      if [[ $cleaned -eq 1 ]] || [[ $jf =~ ^[a-z]+.*$ ]]; then
        ok=1
        echo $(date) $jf >RELEASE
        zip -q -u $target/$jf RELEASE
        if [[ "$mode" == "1" ]]; then
          echo $target/$jf $target/lib-$n.jar
          mv $target/$jf $target/lib-$n.jar
        fi
      fi
      n=$((n + 1))
    fi
  done
}

if [[ -z $build_file ]]; then
  ${SPARK_HOME}/bin/docker-image-tool.sh -n -r ${REPO} -t ${image_tag} ${BUILD_PARAMS} -p ${SPARK_HOME}/kubernetes/dockerfiles/spark/Dockerfile build
else
  rm ${SPARK_HOME}/jars/snappy-java-1.1.10.3.jar
  clean_unused_files "$SPARK_HOME"/jars "jquery.*.js$" "avro-ipc.*.jar"
  clean_unused_files "$SPARK_HOME"/jars

  docker buildx build --platform "$PLATFORMS" --no-cache -t ${REPO}/spark:"${image_tag}" "${SPARK_HOME}" --push -f ${build_file}
fi
