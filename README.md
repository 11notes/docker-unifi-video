# docker-unifi

Small container with unifi controller installed

## Volumes

/var/log/unifi-video

Purpose: Unifi-Video log files

/var/lib/unifi-videos

Purpose: Univi-Video installation directory with settings, etc

/var/lib/unifi-video/videos

Purpose: The actual video recordings are stored in this folder

## Run
```shell
docker run --name unifi-video \
    -v volume-log:/var/log/unifi-video \
    -v volume-data:/var/lib/unifi-videos \
    -v volume-videos:/var/lib/unifi-video/videos \
    -d 11notes/unifi-video:latest
```

## Docker -u 1000:1000 (no root initiative)

As part to make containers more secure, this container will not run as root, but as uid:gid 1000:1000. To achiev this, several features that require root were dismissed (tempfs, chown/chmod of certain files, upstart script, PID). The original upstart script (unifi-video.original.sh) is attached to this repo.

## Build with
* [Ubuntu](https://hub.docker.com/_/ubuntu) - Parent container
* [Ubiquiti Unifi Video](https://community.ubnt.com/t5/UniFi-Video-Blog/bg-p/blog_airVision) - Unifi Update Blog

## Tips

* Don't bind to ports < 1024 (requires root), use NAT
* [Permanent Storge with NFS/CIFS/...](https://github.com/11notes/alpine-docker-netshare) - Module to store permanent container data via NFS/CIFS/...