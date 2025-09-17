FROM python:3.12-slim-bookworm

LABEL maintainer="Andreas Peters <support@aventer.biz>"
LABEL org.opencontainers.image.title="marathon-lb"
LABEL org.opencontainers.image.description="Loadbalancer for Mesosphere Marathon"
LABEL org.opencontainers.image.vendor="AVENTER UG (haftungsbeschränkt)"
LABEL org.opencontainers.image.source="https://github.com/AVENTER-UG/"

# Never prompts the user for choices on installation/configuration of packages
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=linux

# Define en_US.
ENV LC_ALL="C.utf8"
ENV LC_CTYPE="C.utf8"

# runtime dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        ca-certificates \
        iptables \
        libcurl4 \
        libssl3 \
        openssl \
        procps \
        python3 \
        runit \
        gnupg-agent \
        gpg  \
        dirmngr \
        socat \
        cargo \
        make \
    && rm -rf /var/lib/apt/lists/*

ENV TINI_VERSION=v0.19.0 \
    TINI_GPG_KEY=595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7

ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini.asc /tini.asc    

RUN gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
    && gpg --batch --verify /tini.asc /tini

RUN set -x \
    && apt-get update && apt-get install -y --no-install-recommends dirmngr gpg wget \
    && rm -rf /var/lib/apt/lists/* \
    && wget --no-check-certificate -O tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-amd64" \
    && wget --no-check-certificate -O tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-amd64.asc" 

RUN export GNUPGHOME="$(mktemp -d)" 
RUN gpg --auto-key-locate keyserver --locate-key "$TINI_GPG_KEY" 
#RUN gpg --batch --verify tini.asc tini 

RUN rm -rf "$GNUPGHOME" tini.asc \
    && mv tini /usr/bin/tini \
    && chmod +x /usr/bin/tini \
    && tini -- true \
    && apt-get purge -y --auto-remove gpg dirmngr 


ENV HAPROXY_MAJOR=3.2 \
    HAPROXY_VERSION=3.2.4 \
    HAPROXY_MD5=35a9600a063df8d85fd845dc330cb111

COPY requirements.txt /marathon-lb/

RUN set -x \
    && buildDeps=' \
        build-essential \
        gcc \
        libcurl4-openssl-dev \
        libffi-dev \
        liblua5.3-dev \
        libpcre3-dev \
        libssl-dev \
        python3-dev \
        python3-pip \
        python3-setuptools \
        wget \
        zlib1g-dev \
    ' \
    && apt-get update \
    && apt-get install -y --no-install-recommends $buildDeps \
    && rm -rf /var/lib/apt/lists/*

# Build HAProxy
RUN wget --no-check-certificate -O haproxy.tar.gz "https://www.haproxy.org/download/$HAPROXY_MAJOR/src/haproxy-$HAPROXY_VERSION.tar.gz" \
    && echo "$HAPROXY_MD5  haproxy.tar.gz" | md5sum -c \
    && mkdir -p /usr/src/haproxy \
    && tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1 \
    && rm haproxy.tar.gz 

RUN make -C /usr/src/haproxy \
        TARGET=linux-glibc \
        ARCH=x86_64 \
        USE_LUA=1 \
        LUA_INC=/usr/include/lua5.3/ \
        USE_OPENSSL=1 \
        USE_PCRE_JIT=1 \
        USE_PCRE=1 \
        USE_REGPARM=1 \
        USE_STATIC_PCRE=1 \
        USE_ZLIB=1 \
        USE_PROMEX=1 \
        all \
        install-bin 

RUN rm -rf /usr/src/haproxy

RUN python3 -m venv /marathon-lb/venv
RUN . /marathon-lb/venv/bin/activate

ENV PATH=/marathon-lb/venv/bin:$PATH

# Install Python dependencies
# Install Python packages with --upgrade so we get new packages even if a system
# package is already installed. Combine with --force-reinstall to ensure we get
# a local package even if the system package is up-to-date as the system package
# will probably be uninstalled with the build dependencies.
RUN pip3 install --no-cache --upgrade --force-reinstall -r /marathon-lb/requirements.txt \
    && apt-get purge -y --auto-remove $buildDeps

RUN update-alternatives --set iptables /usr/sbin/iptables-legacy

COPY  . /marathon-lb
RUN rm -rf /marathon-lb/.git
RUN rm -rf /marathon-lb/.github

WORKDIR /marathon-lb

ENTRYPOINT [ "tini", "-g", "--", "/marathon-lb/run" ]
CMD [ "sse", "--health-check", "--group", "external" ]



EXPOSE 80 443 9090 9091
