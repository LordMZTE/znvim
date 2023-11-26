#!/bin/bash
set -ex

nvimdir="_nvim"
outfile="nvim_c.zig"

git clone --depth 1 'https://github.com/neovim/neovim.git' $nvimdir

mkdir $nvimdir/build
pushd $nvimdir/build
# Build required due to tons of generated headers
cmake ..
make -j"$(nproc)"
popd

echo "// Generated by $0" >$outfile
zig translate-c \
	nvim_all.h \
	-lluajit-5.1 \
	-I"$nvimdir"/src \
	-I"$nvimdir"/build/src \
	-I"$nvimdir"/build/src/nvim/auto \
	-I"$nvimdir"/build/cmake.config \
	-I"$nvimdir"/build/include \
	-DINCLUDE_GENERATED_DECLARATIONS=1 \
	>>$outfile

rm -rf $nvimdir
