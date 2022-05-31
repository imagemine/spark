#!/usr/bin/env bash
set -e
source build.properties


current_hash=$(git log --pretty=format:'%h' --max-count=1)
current_branch=$(git branch --show-current|sed 's#/#_#')

build_version=""

create_tag() {
    if [[ ${current_branch} == "main" ]];
    then
        git fetch --tags --force
        current_version_at_head=$(git tag --points-at HEAD)
        if [[ -z ${current_version_at_head} ]] || [[ ! "${current_version_at_head}" =~ ^b+ ]];
        then
            commit_hash=$(git rev-list --tags --topo-order --max-count=1)
            latest_version=""
            if [[ "${commit_hash}" != "" ]]; then
              latest_version=$(git describe --tags ${commit_hash} 2>/dev/null)
            fi;
            if [[ ${latest_version} =~ ^b+ ]];
            then
                read a b c <<< $(echo $latest_version|sed 's/\./ /g')
                build_version="$a.$b.$((c+1))"
            else
                build_version="b1.0.0"
            fi;
	          echo "build version: ${build_version}"
        else
            echo nothing to build
        fi;
    fi;
}

all() {
  create_tag
  if [[ ! -z ${build_version} ]];
  then

    for v in $(echo $version|sed s/","/" "/g);
    do 
      ./spark-builder.sh ${v}
      docker tag ${owner}/${artifact}:${v} ${owner}/${artifact}:${v}-${build_version}
      docker push ${owner}/${artifact}:${v}-${build_version}
    done;

    now=$(date '+%Y-%m-%dT%H:%M:%S%z')

    git config --global user.email "${email}"
    git config --global user.name "${name}"

    git tag -m "{\"author\":\"ci\", \"branch\":\"$current_branch\", \"hash\": \"${current_hash}\", \"version\":\"${build_version}\",  \"build_date\":\"${now}\"}"  ${build_version}
    git push --tags
  fi;
}



cmd=$1

case $cmd in
  latest)
   _latest
  ;;
  *)
  all
  ;;
esac;

