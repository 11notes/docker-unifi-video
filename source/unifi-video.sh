#!/bin/sh
# Ubiquiti unifi-video service script            -*- shell-script -*-
# Copyright (c) 2013-2015 Ubiquiti Networks, Inc. http://www.ubnt.com
# vim: ft=sh

set -e

NAME=unifi-video
PKGUSER=unifi-video

BASEDIR="/usr/lib/${NAME}"
DATADIR="${BASEDIR}/data"
PIDFILE="/var/run/${NAME}/${NAME}.pid"
TMPFS_DIR="/var/cache/${NAME}"

MAINCLASS="com.ubnt.airvision.Main"
MAINJAR="${BASEDIR}/lib/airvision.jar"

ENABLE_TMPFS=no
TMPFS_SIZE=15%

UFV_VERBOSE=
UFV_DEBUG=
UFV_DAEMONIZE=true
NVR_APPLIANCE=false

# Default java heap to be 1548M if this is an NVR appliance
if grep "ubnt" /proc/version >/dev/null 2>&1; then
  JVM_MAX_HEAP_SZ="1548M"
  NVR_APPLIANCE=true
else
  JVM_MAX_HEAP_SZ=`free -m | awk 'NR==2{printf "%dM\n", $2*0.25 }'`
fi

log_error() {
        printf >2& "(unifi-video) ERROR: $@\n"
}

log_verbose() {
        [ -z "${UFV_VERBOSE}" ] || printf "(unifi-video) $@\n"
}

log_debug() {
        [ -z "${UFV_DEBUG}" ] || printf "(unifi-video) $@\n"
}

log() {
        printf "(unifi-video) $@\n"
}

is_java8_compat() {
        local J V
        J=$1
        V=$($J -version 2>&1 |awk -F\" '{print $2}')
        case "$V" in
                1.8*) return 0
                ;;
        esac
        return 1
}

java_autodetect() {
        JAVA=$(readlink -e $(which java))
        JAVA_HOME=

        for f in $1 ${JAVA} /usr/lib/jvm/*/bin/java; do
                if is_java8_compat $f; then
                        JAVA_HOME=$(dirname $(dirname $f))
                        JAVA=$f
                        break
                fi
        done
}

update_limits() {
        grep -q -F '* hard nofile 65534' /etc/security/limits.conf ||
                sed -ie '/End of file/ i\* hard nofile 65534'  /etc/security/limits.conf
        grep -q -F '* soft nofile 65534' /etc/security/limits.conf ||
                sed -ie '/End of file/ i\* soft nofile 65534'  /etc/security/limits.conf
        sed -i '/pam_limits.so/c\session required pam_limits.so' /etc/pam.d/su
}

prepare_tmpfs() {
        local DIR SIZE PKGUSERID MNT_OPTIONS
        DIR=$1
        SIZE=$2
        PKGUSERID=$(id -u ${PKGUSER})
        MNT_OPTIONS="noatime,nodiratime,noexec,size=${SIZE},mode=0700"
        [ -z "${PKGUSERID}" ] || MNT_OPTIONS="${MNT_OPTIONS},uid=${PKGUSERID}"

        mkdir -p ${DIR} || true
        chmod -R 0700 ${DIR}
        if mountpoint -q ${DIR}; then
                mount -o remount,${MNT_OPTIONS} ${DIR}
        else
                mount -t tmpfs -o ${MNT_OPTIONS} tmpfs ${DIR}
        fi
}


require_root() {
        [ -z "${EUID}" ] && EUID=$(id -u)
        if [ "x${EUID}" != "x0" ]; then
                log_error "This program requires administrative privileges."
                exit 1
        fi
}

pidfile_info() {
        local pidfile pid
        pidfile=$1
        [ -r "${pidfile}" ] || return 4

        read pid < "${pidfile}"
        if $(kill -0 "${pid}" 2>/dev/null); then
                printf "${pid}"
                return 0
        elif $(ps "${pid}" >/dev/null 2>&1); then
                printf "${pid}"
                return 0
        else
                return 1
        fi

        return 4
}

is_service_pid() {
        local pid
        pid=$1
        if grep "${MAINCLASS}" /proc/${pid}/cmdline >/dev/null 2>&1; then
                return 0
        else
                return 1
        fi
}

is_service_running() {
        local pidfile pid rc PIDOF pids
        pidfile=$1
        rc=0
        pid=$(pidfile_info "${pidfile}") || rc=$?
        if [ "$rc" = "0" ]; then
                if is_service_pid "${pid}"; then
                        echo "${pid}"
                        return 0
                else
                        rm -f "${pidfile}" || true
                        return 1
                fi
        else
                # pidfile is either missing or invalid
                rm -f "${pidfile}" || true
                # try pidof if it exists
                PIDOF=$(command -v pidof 2>/dev/null)
                [ -z "${PIDOF}" ] && return 1
                pids=$(${PIDOF} ${JSVC})
                for pid in ${pids}; do
                        if is_service_pid "${pid}"; then
                                echo "${pid}"
                                return 0
                        fi
                done
                return 1
        fi
}

usage() {
        printf \
"unifi-video service utility, (c) 2013-2015 Ubiquiti Networks, Inc.\n\
Usage: $(basename $0) [options] <start|stop>\n\
\t-h,--help    \tprint this help and quit\n\
\t-D,--nodetach\tdon't detach from parent process\n\
\t-v,--version \tprint version and quit\n\n\
The following environment variables can be used to tune service parameters:\n\
\tJAVA_HOME\tpreferred Java environment\n\
\tJVM_MX\tmaximum heap size for JVM (see java -Xmx option for valid values)\n\
\t
"
}

# rudimentary option parsing
ACTION=help
for arg in $@; do
        case "${arg}" in
        start|stop|status)
                ACTION=${arg}
                ;;
        -h|--help)
                ACTION=help
                ;;
        -g|--verbose)
                UFV_VERBOSE=true
                ;;
        -D|--nodetach)
                UFV_DAEMONIZE=false
                ;;
        --debug)
                UFV_DEBUG=true
                ;;
        -v|-V|--version)
                ACTION=version
                ;;
        esac
done

if [ "x${ACTION}" = "xhelp" ]; then
        usage
        exit 1
fi

[ -n "${JAVA_HOME}" ] && ENV_JAVA="${JAVA_HOME}"/bin/java

java_autodetect ${ENV_JAVA}


if [ -z "$JAVA_HOME" ]; then
  log_error "no suitable Java 8 environment found!"
  exit 1
fi

log_debug "Java Runtime: ${JAVA_HOME}"

JSVC=$(command -v jsvc)
if [ $? -ne 0 ]; then
        log_error "jsvc is missing!"
        exit 1
fi
log_debug "JSVC: ${JSVC}"

[ -z "${JVM_MX}" ] && JVM_MX=${JVM_MAX_HEAP_SZ}
[ -z "${JVM_JMXREMOTE_PORT}" ] && JVM_JMXREMOTE_PORT=7654
JSVC_EXTRA_OPTS=
[ -f /etc/default/${NAME} ] && . /etc/default/${NAME}

if [ -n "${AV_DATADIR}" ]; then
        DATADIR="${AV_DATADIR}"
        JSVC_EXTRA_OPTS="${JSVC_EXTRA_OPTS} -Dav.datadir=${AV_DATADIR}"
fi

if [ "x${ENABLE_TMPFS}" = "xyes" ]; then
        JSVC_EXTRA_OPTS="${JSVC_EXTRA_OPTS} -Dav.tempdir=${TMPFS_DIR}"
fi

[ -e /dev/urandom ] && \
        JVM_EXTRA_OPTS="-Djava.security.egd=file:/dev/./urandom ${JVM_EXTRA_OPTS}"

JVM_OPTS="${JVM_EXTRA_OPTS} \
 -Xms${JVM_MX} \
 -Xmx${JVM_MX} \
 -XX:+HeapDumpOnOutOfMemoryError \
 -XX:+UseG1GC \
 -XX:+UseStringDeduplication \
 -Djava.library.path=${BASEDIR}/lib \
 -Djava.awt.headless=true \
 -Djavax.net.ssl.trustStore=${DATADIR}/ufv-truststore \
 -Dfile.encoding=UTF-8"

# check whether jsvc requires -cwd option
if ${JSVC} -java-home ${JAVA_HOME} -cwd / -help >/dev/null 2>&1; then
        JSVC_OPTS="${JSVC_OPTS} -cwd ${BASEDIR}"
fi

if [ -n "${UFV_DEBUG}" ]; then
        JSVC_OPTS="${JSVC_OPTS} -debug"
        JVM_OPTS="${JVM_OPTS} \
                 -Dcom.sun.management.jmxremote \
                 -Dcom.sun.management.jmxremote.ssl=false \
                 -Dcom.sun.management.jmxremote.authenticate=false \
                 -Dcom.sun.management.jmxremote.port=${JVM_JMXREMOTE_PORT}"
        [ -z "${JVM_JMXREMOTE_HOST}" ] && \
                JVM_JMXREMOTE_HOST=$(hostname -I | cut -d' ' -f1)
        [ -z "${JVM_JMXREMOTE_HOST}" ] || \
                JVM_OPTS="${JVM_OPTS} -Djava.rmi.server.hostname=${JVM_JMXREMOTE_HOST}"

fi
[ "x${UFV_DAEMONIZE}" != "xtrue" ] && JSVC_OPTS="${JSVC_OPTS} -nodetach"

JSVC_OPTS="${JSVC_OPTS} \
 -user ${PKGUSER} \
 -home ${JAVA_HOME} \
 -cp /usr/share/java/commons-daemon.jar:${MAINJAR} \
 -pidfile ${PIDFILE} \
 -procname ${NAME} \
 ${JSVC_EXTRA_OPTS} \
 ${JVM_OPTS}"


log_debug "\nJVM options: ${JSVC_EXTRA_OPTS} ${JVM_OPTS}"
log_debug "\nJSVC options: ${JSVC_OPTS}"

waitfor_srv_mountpoint() {


 if [ "x${NVR_APPLIANCE}" = "xtrue" ]; then

    # wait 60s for the /srv partition to be mounted
    # update system.properties if it is missing
    # if not mounted, exit the script with an error
    UFV_MOUNT_POINT="/srv"
    TIMEOUT=600
    log "waiting for $UFV_MOUNT_POINT to be mounted..."
    while ! mountpoint -q $UFV_MOUNT_POINT; do
      sleep 0.1
      TIMEOUT=$(( $TIMEOUT - 1 ))
      if [ $TIMEOUT -le 0 ]; then
        log "ERROR: Failed to start unifi-video. $UFV_MOUNT_POINT is not mounted"
        exit 10
      fi
    done
  fi
  log "checking for system.properties and truststore files..."
  if  [ ! -f "${DATADIR}/system.properties" ]; then
    log "WARNING!!!! system.properties cannot be found..restoring from : ${BASEDIR}/etc/system.propetties"
    cp  -f "${BASEDIR}/etc/system.properties" "${DATADIR}/system.properties"
  fi

  [ ! -f "${DATADIR}/truststore" ] && rm -f "${DATADIR}/truststore"
  [ -f "${DATADIR}/ufv-truststore" ] || cp -f "${BASEDIR}/etc/ufv-truststore" "${DATADIR}/ufv-truststore"
  #chown -h ${PKGUSER}:${PKGUSER} "${DATADIR}" "${DATADIR}/system.properties" "${DATADIR}/ufv-truststore"  "/var/run/unifi-video/${NAME}"
}


case $ACTION in
        start)
        #require_root
        #update_limits
        ulimit -H -c 200
        echo 0x10 > /proc/self/coredump_filter
                if is_service_running "${PIDFILE}" >/dev/null; then
                        log_verbose "${NAME} is already running..."
                else
                        [ -d /var/run/unifi-video/${NAME} ] || mkdir -p /var/run/unifi-video/${NAME}
                        [ "x${ENABLE_TMPFS}" = "xyes" ] && prepare_tmpfs ${TMPFS_DIR} ${TMPFS_SIZE}
                        [ -d "${BASEDIR}/work/Catalina" ] && rm -rf "${BASEDIR}/work/Catalina"

                        waitfor_srv_mountpoint
                        log_verbose "Starting ${NAME}..."
                        cd "${BASEDIR}" 
                        exec ${JSVC} ${JSVC_OPTS} ${MAINCLASS} start
                fi
                ;;
        stop)
        #require_root
        ulimit -H -c 200

        log_verbose "Backing up ${DATADIR}/system.properties in ${BASEDIR}/etc/system.properties"
        cp -f "${DATADIR}/system.properties" "${BASEDIR}/etc/system.properties"

        echo 0x10 > /proc/self/coredump_filter
                rc=0
                pid=$(is_service_running ${PIDFILE}) || rc=$?
                if [ "0" = "${rc}" ]; then
                        # jsvc won't even try to do anything if pidfile is missing..
                        [ -e "${PIDFILE}" ] || echo "${pid}" > ${PIDFILE}
                        log_verbose "Stopping ${NAME}..."
                        cd "${BASEDIR}" && exec ${JSVC} ${JSVC_OPTS} -stop ${MAINCLASS} stop
                else
                        log_verbose "${NAME} is not running"
                fi
                ;;
        status)
                log_verbose "Checking status of ${NAME}..."
                rc=0
                pid=$(is_service_running ${PIDFILE}) || rc=$?
                if [ "0" = "${rc}" ]; then
                        log_verbose "${NAME} is running, PID: ${pid}"
                else
                        log_verbose "${NAME} is NOT running"
                fi

                exit ${rc}
                ;;
        version)
                cd ${BASEDIR} && ${JAVA} -jar ${MAINJAR} --version
                ;;
esac