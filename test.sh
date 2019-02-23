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

echo "[BUILD] example"
$RUSTC example/example.rs --crate-type lib

echo "[JIT] mini_core_hello_world"
CG_CLIF_JIT=1 CG_CLIF_JIT_ARGS="abc bcd" $RUSTC --crate-type bin -Cprefer-dynamic example/mini_core_hello_world.rs --cfg jit

echo "[AOT] mini_core_hello_world"
$RUSTC example/mini_core_hello_world.rs --crate-name mini_core_hello_world --crate-type bin -g
./target/out/mini_core_hello_world abc bcd
# (echo "break set -n main"; echo "run"; sleep 1; echo "si -c 10"; sleep 1; echo "frame variable") | lldb -- ./target/out/mini_core_hello_world abc bcd

echo "[AOT] arbitrary_self_types_pointers_and_wrappers"
$RUSTC example/arbitrary_self_types_pointers_and_wrappers.rs --crate-name arbitrary_self_types_pointers_and_wrappers --crate-type bin
./target/out/arbitrary_self_types_pointers_and_wrappers

echo "[BUILD] sysroot"
time ./build_sysroot/build_sysroot.sh

echo "[AOT] alloc_example"
$RUSTC example/alloc_example.rs --crate-type bin
./target/out/alloc_example

echo "[JIT] std_example"
CG_CLIF_JIT=1 $RUSTC --crate-type bin -Cprefer-dynamic example/std_example.rs

echo "[AOT] dst_field_align"
# FIXME Re-add -Zmir-opt-level=2 once rust-lang/rust#67529 is fixed.
$RUSTC example/dst-field-align.rs --crate-name dst_field_align --crate-type bin
./target/out/dst_field_align

echo "[AOT] std_example"
$RUSTC example/std_example.rs --crate-type bin
./target/out/std_example

echo "[AOT] subslice-patterns-const-eval"
$RUSTC example/subslice-patterns-const-eval.rs --crate-type bin -Cpanic=abort
./target/out/subslice-patterns-const-eval

echo "[AOT] track-caller-attribute"
$RUSTC example/track-caller-attribute.rs --crate-type bin -Cpanic=abort
./target/out/track-caller-attribute

echo "[BUILD] mod_bench"
$RUSTC example/mod_bench.rs --crate-type bin

# FIXME linker gives multiple definitions error on Linux
#echo "[BUILD] sysroot in release mode"
#./build_sysroot/build_sysroot.sh --release

git clone https://github.com/rust-lang/rust.git --single-branch || true
cd rust
#git fetch
#git checkout -f $(rustc -V | cut -d' ' -f3 | tr -d '(')
export RUSTFLAGS=
export CG_CLIF_DISPLAY_CG_TIME=

#git apply ../rust_lang.patch


rm config.toml || true

cat > config.toml <<EOF
[rust]
codegen-backends = []
deny-warnings = false
[build]
local-rebuild = true
rustc = "$HOME/.rustup/toolchains/$(cat ../rust-toolchain)-$TARGET_TRIPLE/bin/rustc"
EOF

git checkout $(rustc -V | cut -d' ' -f3 | tr -d '(') src/test
rm -r src/test/ui/{asm-*,abi*,extern/,panic-runtime/,panics/,unsized-locals/,proc-macro/,threads-sendsync/,thinlto/,simd*,borrowck/,test*,*lto*.rs} || true
for test in $(rg --files-with-matches "asm!|catch_unwind|should_panic|thread|lto" src/test/ui); do
  rm $test
done
rm src/test/ui/consts/const-size_of-cycle.rs || true # Error file path difference
rm src/test/ui/impl-trait/impl-generic-mismatch.rs || true # ^
rm src/test/ui/type_length_limit.rs || true
rm src/test/ui/issues/issue-50993.rs || true # Target `thumbv7em-none-eabihf` is not supported
rm src/test/ui/macros/same-sequence-span.rs || true # Proc macro .rustc section not found?
rm src/test/ui/suggestions/issue-61963.rs || true # ^

RUSTC_ARGS="-Zpanic-abort-tests -Zcodegen-backend="$(pwd)"/../target/"$CHANNEL"/librustc_codegen_cranelift."$dylib_ext" --sysroot "$(pwd)"/../build_sysroot/sysroot -Cpanic=abort"

echo "[TEST] rustc test suite"
./x.py test --stage 0 src/test/ui/ --rustc-args "$RUSTC_ARGS" 2>&1 | tee log.txt
