FROM debian:bookworm-slim as base

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

ARG ZEEK_LTS=
ARG ZEEK_RC=
ARG ZEEK_DBG=
ARG ZEEK_VERSION=6.0.0-0

ENV ZEEK_LTS $ZEEK_LTS
ENV ZEEK_RC $ZEEK_RC
ENV ZEEK_DBG $ZEEK_DBG
ENV ZEEK_VERSION $ZEEK_VERSION

ENV ZEEK_DIR "/opt/zeek"
ENV PATH "${ZEEK_DIR}/bin:${PATH}"

RUN apt-get -q update && \
    apt-get install -q -y \
      ca-certificates \
      cmake \
      curl \
      g++ && \
    mkdir -p /tmp/zeek-packages && \
      cd /tmp/zeek-packages && \
      if [ -n "${ZEEK_LTS}" ]; then ZEEK_LTS="-lts"; fi && export ZEEK_LTS && \
      if [ -n "${ZEEK_RC}" ]; then ZEEK_RC="-rc"; ln -s -r "${ZEEK_DIR}${ZEEK_RC}" "${ZEEK_DIR}"; fi && export ZEEK_RC && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/all/zeek${ZEEK_LTS}${ZEEK_RC}-btest-data_6.0.0-0_all.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/all/zeek${ZEEK_LTS}${ZEEK_RC}-btest_6.0.0-0_all.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/all/zeek${ZEEK_LTS}${ZEEK_RC}-client_6.0.0-0_all.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/all/zeek${ZEEK_LTS}${ZEEK_RC}-zkg_6.0.0-0_all.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/libbroker${ZEEK_LTS}${ZEEK_RC}-dev_6.0.0-0_amd64.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeek${ZEEK_LTS}${ZEEK_RC}_6.0.0-0_amd64.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeek${ZEEK_LTS}${ZEEK_RC}-core_6.0.0-0_amd64.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeek${ZEEK_LTS}${ZEEK_RC}-core-dev_6.0.0-0_amd64.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeek${ZEEK_LTS}${ZEEK_RC}-spicy-dev_6.0.0-0_amd64.deb" && \
        curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeekctl${ZEEK_LTS}${ZEEK_RC}_6.0.0-0_amd64.deb" && \
        if [ -n "${ZEEK_DBG}" ]; then \
            ZEEK_DBG="-dbgsym" && export ZEEK_DBG && \
            curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeek${ZEEK_LTS}${ZEEK_RC}-core${ZEEK_DBG}_6.0.0-0_amd64.deb" && \
            curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeek${ZEEK_LTS}${ZEEK_RC}-core-dev${ZEEK_DBG}_6.0.0-0_amd64.deb" && \
            curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeek${ZEEK_LTS}${ZEEK_RC}-spicy-dev${ZEEK_DBG}_6.0.0-0_amd64.deb" && \
            curl -fsSL -O -J "https://download.opensuse.org/repositories/security:/zeek/Debian_12/amd64/zeekctl${ZEEK_LTS}${ZEEK_RC}${ZEEK_DBG}_6.0.0-0_amd64.deb"; \
        fi && \
      ( dpkg -i ./*.deb || apt-get -f -y install ) && \
    cd /tmp && \
    zkg autoconfig --force && \
    echo "@load packages" >> "${ZEEK_DIR}"/share/zeek/site/local.zeek && \
    apt-get clean && \
      rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/*/* && \
    echo && \
    echo "Run the container, followed by:" && \
    echo "    $ zkg install --skiptests --force https://github.com/cisagov/icsnpp-synchrophasor" && \
    echo "    $ zeek -NN local" && \
    echo
