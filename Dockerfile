# ------ HEADER ------ #
FROM ubuntu:16.04
ENV unifiVideoVersion=3.9.6
ARG DEBIAN_FRONTEND=noninteractive


# ------ RUN  ------ #
RUN echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.2.list && \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927

RUN apt-get update \
    && apt-get -y install binutils jsvc mongodb-org openjdk-8-jre-headless

RUN apt-get install -y wget dh-python distro-info-data file libmagic1 libmpdec2 libpython3-stdlib libpython3.5-minimal \
    libpython3.5-stdlib lsb-release mime-support psmisc python3 python3-minimal python3.5 python3.5-minimal sudo \
    && wget -O /tmp/uvc.deb https://dl.ubnt.com//firmwares/ufv/v${unifiVideoVersion}/unifi-video.Ubuntu16.04_amd64.v${unifiVideoVersion}.deb \
    && dpkg -i /tmp/uvc.deb \
    && rm -f /tmp/uvc.deb

# ------ VOLUMES ------ #
VOLUME ["/var/lib/unifi-video", "/var/log/unifi-video"]

# ------ CMD/START/STOP ------ #
ENTRYPOINT ["/usr/sbin/unifi-video", "--nodetach", "start"]
CMD ["start"]