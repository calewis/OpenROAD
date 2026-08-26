// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#include "png_encoder.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "parallel_for.h"
#include "third-party/lodepng/lodepng.h"
#include "utl/ThreadPool.h"
#include "zlib.h"

namespace web {

namespace {

struct ZlibContext
{
  utl::ThreadPool* pool;
  int threads;
};

// lodepng custom_zlib hook: compresses `in` into a malloc'd `*out` (lodepng
// releases it with free()).  Returns 0 on success.
unsigned parallelZlib(unsigned char** out,
                      size_t* outsize,
                      const unsigned char* in,
                      const size_t insize,
                      const LodePNGCompressSettings* settings)
{
  const auto* ctx = static_cast<const ZlibContext*>(settings->custom_context);

  // Bands of at least kMinBand bytes: deflate's 32 KiB window restarts at
  // every band, so very small bands cost compression ratio for no speedup.
  constexpr size_t kMinBand = 512 * 1024;
  const int max_bands = std::max<int>(1, static_cast<int>(insize / kMinBand));
  const int bands = std::clamp(max_bands, 1, std::max(1, ctx->threads));
  const size_t band_size = (insize + bands - 1) / bands;

  std::vector<std::vector<unsigned char>> parts(bands);
  std::vector<uLong> adlers(bands, 0);
  std::vector<int> errors(bands, Z_OK);

  auto deflate_band = [&](const int i) {
    const size_t begin = i * band_size;
    const size_t len = std::min(band_size, insize - begin);
    const bool last = (i == bands - 1);

    z_stream zs;
    std::memset(&zs, 0, sizeof(zs));
    // Raw deflate (negative windowBits): the zlib framing is added once,
    // around the concatenated bands, below.
    int rc = deflateInit2(&zs,
                          Z_DEFAULT_COMPRESSION,
                          Z_DEFLATED,
                          /*windowBits=*/-15,
                          /*memLevel=*/8,
                          Z_DEFAULT_STRATEGY);
    if (rc != Z_OK) {
      errors[i] = rc;
      return;
    }
    // deflateBound covers Z_FINISH; the sync-flush trailer (an empty stored
    // block) needs a few more bytes.
    std::vector<unsigned char>& part = parts[i];
    part.resize(deflateBound(&zs, len) + 16);
    zs.next_in = const_cast<Bytef*>(in + begin);
    zs.avail_in = static_cast<uInt>(len);
    zs.next_out = part.data();
    zs.avail_out = static_cast<uInt>(part.size());
    rc = deflate(&zs, last ? Z_FINISH : Z_SYNC_FLUSH);
    const bool ok
        = last ? (rc == Z_STREAM_END) : (rc == Z_OK && zs.avail_in == 0);
    part.resize(zs.total_out);
    deflateEnd(&zs);
    if (!ok) {
      errors[i] = rc == Z_OK ? Z_BUF_ERROR : rc;
      return;
    }
    adlers[i]
        = adler32(adler32(0L, Z_NULL, 0), in + begin, static_cast<uInt>(len));
  };
  parallelFor(ctx->pool, ctx->threads, bands, deflate_band);

  for (const int rc : errors) {
    if (rc != Z_OK) {
      return 1;
    }
  }

  // Assemble: zlib header, the raw bands, then the Adler-32 of the whole
  // input (combined from the per-band values).
  size_t total = 2 + 4;
  for (const auto& part : parts) {
    total += part.size();
  }
  auto* buf = static_cast<unsigned char*>(std::malloc(total));
  if (buf == nullptr) {
    return 83;  // lodepng's "alloc fail"
  }
  unsigned char* p = buf;
  *p++ = 0x78;  // CM = 8 (deflate), CINFO = 7 (32 KiB window)
  *p++ = 0x9c;  // FLEVEL = default, FDICT = 0, FCHECK
  uLong adler = adler32(0L, Z_NULL, 0);
  for (int i = 0; i < bands; ++i) {
    std::memcpy(p, parts[i].data(), parts[i].size());
    p += parts[i].size();
    const size_t begin = i * band_size;
    const size_t len = std::min(band_size, insize - begin);
    adler = adler32_combine(adler, adlers[i], static_cast<z_off_t>(len));
  }
  *p++ = static_cast<unsigned char>(adler >> 24);
  *p++ = static_cast<unsigned char>(adler >> 16);
  *p++ = static_cast<unsigned char>(adler >> 8);
  *p++ = static_cast<unsigned char>(adler);

  *out = buf;
  *outsize = total;
  return 0;
}

}  // namespace

std::vector<unsigned char> encodePng(const std::vector<unsigned char>& rgba,
                                     const int width,
                                     const int height,
                                     utl::ThreadPool* pool,
                                     const int threads,
                                     unsigned* error)
{
  ZlibContext ctx{pool, std::max(1, threads)};

  lodepng::State state;
  state.info_raw.colortype = LCT_RGBA;
  state.info_raw.bitdepth = 8;
  state.info_png.color.colortype = LCT_RGBA;
  state.info_png.color.bitdepth = 8;
  // Keep RGBA rather than letting lodepng scan the image for a smaller
  // colour type: the scan is a full extra pass and the viewer draws RGBA.
  state.encoder.auto_convert = 0;
  state.encoder.zlibsettings.custom_zlib = &parallelZlib;
  state.encoder.zlibsettings.custom_context = &ctx;

  std::vector<unsigned char> png;
  const unsigned err = lodepng::encode(png, rgba, width, height, state);
  if (error != nullptr) {
    *error = err;
  }
  if (err != 0) {
    return {};
  }
  return png;
}

}  // namespace web
