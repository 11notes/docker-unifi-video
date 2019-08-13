# :: Header
FROM ubuntu:16.04
ENV unifiVideoVersion=3.10.6
ARG DEBIAN_FRONTEND=noninteractive

# :: Run
RUN echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.2.list && \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927

RUN apt-get update \
    && apt-get -y install binutils jsvc mongodb-org openjdk-8-jre-headless

RUN mkdir -p /var/run/unifi-video

RUN apt-get install -y wget curl dh-python distro-info-data file libmagic1 libmpdec2 libpython3-stdlib libpython3.5-minimal \
    libpython3.5-stdlib lsb-release mime-support psmisc python3 python3-minimal python3.5 python3.5-minimal sudo \
    && wget -O /tmp/uvc.deb https://dl.ubnt.com/firmwares/ufv/v${unifiVideoVersion}/unifi-video.Ubuntu16.04_amd64.v${unifiVideoVersion}.deb \
    && dpkg -i /tmp/uvc.deb \
    && rm -f /tmp/uvc.deb

ADD ./source/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

ADD ./source/unifi-video.sh /usr/local/bin/unifi-video.sh
RUN chmod +x /usr/local/bin/unifi-video.sh

# :: docker -u 1000:1000 (no root initiative)
RUN APP_UID="$(id -u unifi-video)" \
    && APP_GID="$(id -g unifi-video)" \
    && find / -not -path "/proc/*" -user $APP_UID -exec chown -h -R 1000:1000 {} \;\
    && find / -not -path "/proc/*" -group $APP_GID -exec chown -h -R 1000:1000 {} \;
RUN usermod -u 1000 unifi-video \
	&& groupmod -g 1000 unifi-video
RUN chown -R unifi-video:unifi-video \
    /usr/lib/unifi-video \
    /var/lib/unifi-video \
    /var/log/unifi-video \
    /var/run/unifi-video \
    /usr/local/bin

# :: Volumes
VOLUME ["/var/lib/unifi-video", "/var/lib/unifi-video/videos", "/var/log/unifi-video"]

# :: Monitor
HEALTHCHECK CMD /usr/local/bin/healthcheck.sh || exit 1

# :: Start
USER unifi-video
ENTRYPOINT ["/usr/local/bin/unifi-video.sh", "--nodetach", "start"]
CMD ["start"]