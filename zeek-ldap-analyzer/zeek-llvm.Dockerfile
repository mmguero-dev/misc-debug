FROM debian:buster-slim AS build

ENV DEBIAN_FRONTEND noninteractive

# build zeek and plugins (additional protocol parsers, etc.)

ENV BISON_VERSION "3.7.4"
ENV CCACHE_DIR "/var/spool/ccache"
ENV CCACHE_COMPRESS 1
ENV CMAKE_DIR "/opt/cmake"
ENV CMAKE_VERSION "3.19.3"
ENV SRC_BASE_DIR "/usr/local/src"
ENV ZEEK_DIR "/opt/zeek"
ENV ZEEK_PATCH_DIR "${SRC_BASE_DIR}/zeek-patches"
ENV ZEEK_VERSION "3.0.12"
ENV ZEEK_SRC_DIR "${SRC_BASE_DIR}/zeek-${ZEEK_VERSION}"

ENV LLVM_VERSION "11"
ENV CC "clang-${LLVM_VERSION}"
ENV CXX "clang++-${LLVM_VERSION}"
ENV ASM "clang-${LLVM_VERSION}"

ENV PATH "${ZEEK_DIR}/bin:${CMAKE_DIR}/bin:${PATH}"

ADD ldap-analyzer /usr/local/src/ldap-analyzer

RUN sed -i "s/buster main/buster main contrib non-free/g" /etc/apt/sources.list && \
      echo "deb http://deb.debian.org/debian buster-backports main" >> /etc/apt/sources.list && \
      apt-get -q update && \
      apt-get install -q -y --no-install-recommends gnupg2 curl ca-certificates && \
      bash -c "curl -sSL https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -" && \
      echo "deb http://apt.llvm.org/buster/ llvm-toolchain-buster-${LLVM_VERSION} main" >> /etc/apt/sources.list && \
    apt-get -q update && \
    apt-get install -q -y -t buster-backports --no-install-recommends \
        binutils \
        ccache \
        clang-${LLVM_VERSION} \
        file \
        flex \
        git \
        google-perftools \
        jq \
        libclang-${LLVM_VERSION}-dev \
        libfl-dev \
        libgoogle-perftools-dev \
        libkrb5-dev \
        libmaxminddb-dev \
        libpcap0.8-dev \
        libssl-dev \
        llvm-${LLVM_VERSION}-dev \
        locales-all \
        make \
        ninja-build \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        swig \
        zlib1g-dev && \
  pip3 install --no-cache-dir btest pre-commit && \
  mkdir -p "${CMAKE_DIR}" && \
    curl -sSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz" | tar xzf - -C "${CMAKE_DIR}" --strip-components 1 && \
  cd "${SRC_BASE_DIR}" && \
    curl -sSL "https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.gz" | tar xzf - -C "${SRC_BASE_DIR}" && \
    cd "./bison-${BISON_VERSION}" && \
    ./configure --prefix=/usr && \
    make && \
    make install && \
  cd "${SRC_BASE_DIR}" && \
    curl -sSL "https://old.zeek.org/downloads/zeek-${ZEEK_VERSION}.tar.gz" | tar xzf - -C "${SRC_BASE_DIR}" && \
    cd "./zeek-${ZEEK_VERSION}" && \
    ./configure --prefix="${ZEEK_DIR}" --generator=Ninja --ccache --enable-perftools && \
    cd build && \
    ninja && \
    ninja install && \
  cd "${SRC_BASE_DIR}"/ldap-analyzer && \
    ./configure --zeek-dist="${ZEEK_SRC_DIR}" --install-root="${ZEEK_DIR}/lib/zeek/plugins" && \
    make && \
    make install

FROM debian:buster-slim

ARG DEFAULT_UID=1000
ARG DEFAULT_GID=1000
ENV DEFAULT_UID $DEFAULT_UID
ENV DEFAULT_GID $DEFAULT_GID
ENV PUSER "zeek"
ENV PGROUP "zeek"

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

ENV LLVM_VERSION "11"
ENV ZEEK_DIR "/opt/zeek"

COPY --from=build ${ZEEK_DIR} ${ZEEK_DIR}

RUN sed -i "s/buster main/buster main contrib non-free/g" /etc/apt/sources.list && \
      echo "deb http://deb.debian.org/debian buster-backports main" >> /etc/apt/sources.list && \
      apt-get -q update && \
      apt-get install -q -y --no-install-recommends gnupg2 curl ca-certificates && \
      bash -c "curl -sSL https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -" && \
      echo "deb http://apt.llvm.org/buster/ llvm-toolchain-buster-${LLVM_VERSION} main" >> /etc/apt/sources.list && \
    apt-get -q update && \
    apt-get install -q -y -t buster-backports --no-install-recommends \
      binutils \
      file \
      gdb \
      cgdb \
      git \
      libatomic1 \
      libclang-${LLVM_VERSION}-dev \
      libclang-cpp${LLVM_VERSION} \
      libclang-cpp${LLVM_VERSION}-dev \
      libclang1-${LLVM_VERSION} \
      libgoogle-perftools4 \
      libkrb5-3 \
      libmaxminddb0 \
      libpcap0.8 \
      libpcap0.8-dev \
      libssl1.0 \
      libtcmalloc-minimal4 \
      libunwind8 \
      llvm-${LLVM_VERSION} \
      procps \
      psmisc \
      python \
      python3 \
      valgrind \
      vim-tiny && \
    bash -c "( find /opt/zeek/ -type l ! -exec test -r {} \; -print | xargs -r -l rm -vf ) || true" && \
    apt-get -q -y --purge remove libssl-dev && \
      apt-get -q -y autoremove && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#Update Path
ENV PATH "${ZEEK_DIR}/bin:${PATH}"

ADD ldap.pcapng /pcap/ldap.pcapng

RUN groupadd --gid ${DEFAULT_GID} ${PUSER} && \
    useradd -M --uid ${DEFAULT_UID} --gid ${DEFAULT_GID} --home /nonexistant ${PUSER} && \
    usermod -a -G tty ${PUSER} && \
    mkdir /logs && \
    chown -R ${DEFAULT_UID}:${DEFAULT_GID} /pcap /logs

USER ${PUSER}

WORKDIR /logs

ENTRYPOINT ["/opt/zeek/bin/zeek"]

CMD ["-C", "-r", "/pcap/ldap.pcapng", "local"]
