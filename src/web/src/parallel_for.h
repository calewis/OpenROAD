// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#pragma once

#include <algorithm>
#include <vector>

#include "utl/ThreadPool.h"

namespace web {

// Runs fn(i) for i in [0, n) on `pool` (or inline when there is no pool, or
// only one chunk).  Work is dealt round-robin: item i goes to worker
// i % chunks.  Tiles and image rows are far from uniform in cost (die edges
// and the bloat margin are empty, the core is dense), so interleaving balances
// the workers far better than contiguous bands.  The first exception thrown
// by a worker is rethrown here.
template <typename F>
void parallelFor(utl::ThreadPool* pool,
                 const int threads,
                 const int n,
                 const F& fn)
{
  const int chunks = std::min(n, threads);
  if (pool == nullptr || chunks <= 1) {
    for (int i = 0; i < n; ++i) {
      fn(i);
    }
    return;
  }
  std::vector<utl::ThreadPoolFuture<void>> futures;
  futures.reserve(chunks);
  for (int t = 0; t < chunks; ++t) {
    futures.push_back(pool->submit([&fn, t, n, chunks]() {
      for (int i = t; i < n; i += chunks) {
        fn(i);
      }
    }));
  }
  // get() (not wait()) so an exception thrown in a worker propagates to the
  // caller instead of silently yielding a partial result.
  for (auto& f : futures) {
    f.get();
  }
}

}  // namespace web
