FROM cloudnativek8s/microservices-java17-alpine-u10k:v1.0.30
# docker build -t spark:latest -f kubernetes/dockerfiles/spark/Dockerfile .
ARG spark_uid=10000
USER root

RUN set -ex && \
    apk update && apk upgrade libx11 && apk add tini zip && ln -s /sbin/tini /usr/bin/tini && \
    mkdir -p /opt/spark && \
    mkdir -p /opt/spark/examples && \
    mkdir -p /opt/spark/work-dir && \
    touch /opt/spark/RELEASE && \
    rm /bin/sh && \
    ln -sv /bin/bash /bin/sh && \
    rm -rf /var/cache/apt/*

COPY jars /opt/spark/jars

COPY bin /opt/spark/bin
COPY sbin /opt/spark/sbin
COPY kubernetes/dockerfiles/spark/entrypoint.sh /opt/
COPY kubernetes/dockerfiles/spark/decom.sh /opt/
COPY kubernetes/tests /opt/spark/tests
COPY data /opt/spark/data

ENV SPARK_HOME /opt/spark

WORKDIR /opt/spark/work-dir
RUN chmod g+w /opt/spark/work-dir
RUN chmod a+x /opt/decom.sh

RUN chown -R ${spark_uid}:${spark_uid} /opt/spark /opt/app
USER ${spark_uid}

ENTRYPOINT [ "/opt/entrypoint.sh" ]


