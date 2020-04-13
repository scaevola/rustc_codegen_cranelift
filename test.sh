#!/bin/bash

set -e

if [[ "$1" == "--release" ]]; then
    export CHANNEL='release'
    CARGO_INCREMENTAL=1 cargo rustc --release -- -Zrun_dsymutil=no
else
    export CHANNEL='debug'
    cargo rustc -- -Zrun_dsymutil=no
fi

source config.sh

rm -r target/out || true
mkdir -p target/out/clif

echo "[BUILD] mini_core"
$RUSTC example/mini_core.rs --crate-name mini_core --crate-type lib,dylib

echo "[AOT] mini_core_hello_world"
$RUSTC example/mini_core_hello_world.rs --crate-name mini_core_hello_world --crate-type bin -g
qemu-aarch64 -E LD_LIBRARY_PATH=/usr/aarch64-linux-gnu/lib ./target/out/mini_core_hello_world abc bcd
