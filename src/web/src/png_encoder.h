// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#pragma once

#include <vector>

namespace utl {
class ThreadPool;
}

namespace web {

// Encodes a top-down RGBA8 buffer as a PNG.  The IDAT zlib stream is built
// pigz-style: the filtered scanlines are split into bands, each band is
// deflated on its own worker (Z_SYNC_FLUSH ends a band's blocks on a byte
// boundary with BFINAL clear), and the bands are concatenated under one zlib
// header with a combined Adler-32.  Any inflater reads the result as a single
// stream.  With no pool (or one thread) it is a plain single-threaded encode.
// Returns an empty vector on error and reports the lodepng error code through
// `error` when given.
std::vector<unsigned char> encodePng(const std::vector<unsigned char>& rgba,
                                     int width,
                                     int height,
                                     utl::ThreadPool* pool,
                                     int threads,
                                     unsigned* error = nullptr);

}  // namespace web
