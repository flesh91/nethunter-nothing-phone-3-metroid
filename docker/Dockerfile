FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang-18 lld-18 llvm-18 bc bison flex libssl-dev libelf-dev make python3 cpio kmod \
    git ca-certificates rsync xz-utils lz4 zstd dwarves file zip unzip curl patch perl \
 && rm -rf /var/lib/apt/lists/* \
 && for t in clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-strip llvm-readobj llvm-ranlib llvm-dwarfdump; do ln -sf /usr/bin/$t-18 /usr/local/bin/$t; done \
 && ln -sf /usr/bin/clang-18 /usr/local/bin/clang && ln -sf /usr/bin/ld.lld-18 /usr/local/bin/ld.lld
WORKDIR /work
