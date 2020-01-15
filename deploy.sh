#!/usr/bin/env bash
#
# Copyright (C) 2018-2020 art of coding UG, https://www.art-of-coding.eu
# Alle Rechte vorbehalten. Nutzung unterliegt Lizenzbedingungen.
# All rights reserved. Use is subject to license terms.
#

PREFIX=mikrokosmos
TRAC_PROJECT=MyProject

TRAC_VERSION=1.2.5

#
# DO NOT MODIFY LINES BELOW
#

set -o nounset
set -o errexit

export PREFIX

CURRENT_BRANCH="$(git branch --show-current)"
HEAD_COMMIT_HASH="$(git rev-parse --short HEAD)"
CURRENT_TAG="$(git --no-pager tag -l --points-at HEAD)"
if [ -n "${CURRENT_TAG}" ]
then
    VERSION="${CURRENT_TAG:1}"
else
    VERSION="${CURRENT_BRANCH}-${HEAD_COMMIT_HASH}"
fi
export VERSION

function build_library() {
    local lib=$1
    echo ""
    echo "*"
    echo "* Building ${lib}:${VERSION}"
    echo "*"
    echo ""
    docker build \
        --build-arg "VERSION=${VERSION}" \
        -t "${PREFIX}/${lib}:${VERSION}" \
        "library/${lib}"
    echo "* done"
}

function docker_compose_build() {
    local prj=$1
    docker-compose \
        -p "${PREFIX}" \
        -f "docker-compose.${prj}.yml" \
        build \
        --build-arg "TRAC_PROJECT=${TRAC_PROJECT}" \
        --build-arg "VERSION=${VERSION}"
}

#echo "Mikrokosmos Version ${VERSION}"

cmd=${1:-usage}
case "${cmd}" in
    build-library)
        CONTAINERS=(alpine-latest-stable openssh-base maven postgres redis redis-backup asciidocserver)
        for cnt in "${CONTAINERS[@]}"
        do
            if [[ $(docker image ls | grep "${cnt}" | grep -c "${VERSION}") = 0 ]]
            then
                build_library "${cnt}"
            fi
        done
    ;;
    build-template)
        echo "*"
        echo "* Template: building Endpoint"
        echo "*"
        template/endpoint/endpoint.sh build-images
        echo "* done"
    ;;
    build)
        for cnt in alpine-latest-stable maven postgres
        do
            if [[ $(docker image ls | grep -c "mikrokosmos/${cnt}") = 0 ]]
            then
                build_library "${cnt}"
            fi
        done
        echo ""
        echo "*"
        echo "* Building PM -- trac"
        echo "*"
        echo ""
        docker build \
            --build-arg "VERSION=${VERSION}" \
            --build-arg "TRAC_PROJECT=${TRAC_PROJECT}" \
            --build-arg "TRAC_VERSION=${TRAC_VERSION}" \
            -t "${PREFIX}/trac:${VERSION}" \
            PM/trac
        echo "* done"
        echo ""
        echo "*"
        echo "* Building PM"
        echo "*"
        echo ""
        docker_compose_build pm
        echo "* done"
        echo ""
        echo "*"
        echo "* Building CICD"
        echo "*"
        echo ""
        docker_compose_build cicd
        echo "* done"
        echo ""
        echo "*"
        echo "* Building Reverse Proxy"
        echo "*"
        echo ""
        docker build \
            --build-arg "VERSION=${VERSION}" \
            -t "${PREFIX}/rproxy:${VERSION}" \
            rproxy
        echo "* done"
    ;;
    init)
        $0 stop
        echo ""
        echo "*"
        echo "* Running Project Management, CI/CD and Reverse Proxy"
        echo "*"
        echo ""
        docker-compose \
            -p ${PREFIX} \
            -f docker-compose.yml \
            -f docker-compose.pm.yml \
            -f docker-compose.cicd.yml \
            up -d
        echo "* done"
        echo ""
        echo "* Waiting 15 seconds until all systems are initialized"
        echo ""
        sleep 15
        #YOUTRACK_PWD=$(docker exec \
        #    mikrokosmos_youtrack_1 \
        #    cat /opt/youtrack/conf/internal/services/configurationWizard/wizard_token.txt)
        TRAC_PWD=$(docker logs mikrokosmos_trac-myproject_1 2>&1 \
            | grep "Password is" \
            | awk -F':' '{print $2}' \
            | tr -d ' ')
        NEXUS_PWD=$(docker exec -it mikrokosmos_nexus_1 \
            cat /nexus-data/admin.password)
        echo ""
        echo "**************************************************"
        echo "*"
        echo "* Please adjust your host resolution (/etc/hosts)."
        echo "* See README.adoc."
        echo "*"
        echo "* Point your browser to"
        echo "*"
        #echo "*     http://youtrack.local (${YOUTRACK_PWD})"
        echo "*     http://trac.local (${TRAC_PWD})"
        echo "*     http://redmine.local"
        echo "*     http://repo.local (${NEXUS_PWD})"
        echo "*     http://quality.local"
        echo "*"
        echo "**************************************************"
        echo ""
    ;;
    ps)
        docker-compose \
            -p ${PREFIX} \
            -f docker-compose.yml \
            -f docker-compose.pm.yml \
            -f docker-compose.cicd.yml \
            ps
    ;;
    start)
        docker-compose \
            -p ${PREFIX} \
            -f docker-compose.yml \
            -f docker-compose.pm.yml \
            -f docker-compose.cicd.yml \
            start
    ;;
    stop)
        docker-compose \
            -p ${PREFIX} \
            -f docker-compose.yml \
            -f docker-compose.pm.yml \
            -f docker-compose.cicd.yml \
            stop
    ;;
    *)
        echo "usage: $0 <build-library | build-template | build | run | stop>"
        exit 1
    ;;
esac

exit 0
