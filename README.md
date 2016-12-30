# ffmpeg-build-lambda

> A Travis CI-based :construction_worker: [FFmpeg](https://ffmpeg.org/) build configuration for use on [AWS Lambda](https://aws.amazon.com/lambda/)

[![Build Status](https://travis-ci.org/binoculars/ffmpeg-build-lambda.svg?branch=master)](https://travis-ci.org/binoculars/ffmpeg-build-lambda)

## License
All of the code solely contained in this repository is licensed under the Unlicense. Each of the git submodules and
dependencies are licensed separately. In the current configuration, Specific builds of FFmpeg are licensed under the GPL.
Modification of the build script may result in unredistributable binaries. Please be mindful of this when forking.

## Releases
Check the [releases](./releases/) page for available builds
* Nightly releases are built from the master branches of each of the submodules
* Versioned releases are built when there is a new tag from FFmpeg and the latest tags from libvpx and x265 are used

If you find this useful, please :star2:
