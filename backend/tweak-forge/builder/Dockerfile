# Build once on the builder host: docker build -t mirsa-theos .
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates build-essential perl rsync libtinfo6 xz-utils clang lld libplist-utils fakeroot dpkg unzip && rm -rf /var/lib/apt/lists/*
ENV THEOS=/opt/theos
RUN git clone --recursive --depth 1 https://github.com/theos/theos.git $THEOS \
 && curl -L https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain.tar.xz | tar -xJ -C $THEOS/toolchain \
 && git clone --depth 1 https://github.com/theos/sdks.git /tmp/sdks && cp -r /tmp/sdks/iPhoneOS16*.sdk $THEOS/sdks/ && rm -rf /tmp/sdks
