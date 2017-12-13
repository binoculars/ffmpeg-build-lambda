#!/usr/bin/env bash

set -ev
ROOT=`pwd`
NUM_CORES=2
COMMIT_MSG=$(git --no-pager log -1 --oneline)

if [[ "$TRAVIS_EVENT_TYPE" == 'cron' ]] || [[ "${COMMIT_MSG}" == *'[cron debug]'* ]]; then
	REPO=`git config remote.origin.url`
	SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}

	chmod 600 deploy_key
	eval `ssh-agent -s`
	ssh-add deploy_key

	TODAY=`date -u +%F`

	# Tag the nightly release
	TAG_NAME_TODAY="nightly-${TODAY}"
	if ! git rev-parse -q --verify "refs/tags/${TAG_NAME_TODAY}" >/dev/null; then
		git tag -a "${TAG_NAME_TODAY}" -m "Nightly build for ${TODAY}"
	fi

	# Push updated repo and tags
	git push "${SSH_REPO}" --tags

	exit 0;
fi

# Don't build master, since it will only contain the latest nightly commits.
if [ "${TRAVIS_BRANCH}" == "master" ]; then
	echo "Skipping build for 'master' branch... Just keeping things up-to-date"
	exit 0;
fi

# Update Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get -y install \
	docker-ce \
	figlet

DOCKER_TAG="${QUAY_REPO}:lambda"

# Build the image
docker build \
	--tag "${DOCKER_TAG}-build" \
	--target build \
	.

# Make a dist image (multi-stage)
docker build \
	--cache-from "${DOCKER_TAG}-build" \
	--tag "${DOCKER_TAG}-dist" \
	--tag "${DOCKER_TAG}-${TRAVIS_TAG}" \
	--tag "${DOCKER_TAG}" \
	--target dist \
	.

DIST_DIR=${HOME}/dist
mkdir -p ${DIST_DIR}
docker run -v ${DIST_DIR}:/vol ${DOCKER_TAG} /bin/sh -c 'cp /opt/ffmpeg/bin/* /opt/ffmpeg/COPYING.GPLv3 /vol'

# Generate README.txt
echo "
`figlet -f slant "FFmpeg"`

Build version: ${TRAVIS_TAG}
Build date: `date -u`

`docker run ${DOCKER_TAG} ffmpeg -version`

This build of FFmpeg is licensed under the GPLv3. See the source code for details.

The source code can be downloaded from https://github.com/${TRAVIS_REPO_SLUG}/releases/tag/${TRAVIS_TAG}
" > "${DIST_DIR}/README.txt"

tar -czvf "${TRAVIS_BUILD_DIR}/ffmpeg-build-lambda.tar.gz" -C ${DIST_DIR} .

if [ -n "${TRAVIS_TAG}" ] || [[ "${COMMIT_MSG}" == *'[docker push]'* ]]; then
	docker login -u="${QUAY_USERNAME}" -p="${QUAY_PASSWORD}" quay.io
	
	for tag_suffix in "" "-dist" "-${TRAVIS_TAG}" "-build"; do 
		docker push "${DOCKER_TAG}${tag_suffix}"
	done
fi
