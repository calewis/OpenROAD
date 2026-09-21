# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, The OpenROAD Authors

"""CUDA compile flags and architecture definitions for --config=gpu."""

CUDA_PATH = Label("@cuda_local//:compiler_inputs").workspace_root

CUDA_ARCHS = {
    "sm_100": "BLACKWELL100",
    "sm_103": "BLACKWELL103",
    "sm_120": "BLACKWELL120",
    "sm_121": "BLACKWELL121",
    "sm_60": "PASCAL60",
    "sm_61": "PASCAL61",
    "sm_70": "VOLTA70",
    "sm_72": "VOLTA72",
    "sm_75": "TURING75",
    "sm_80": "AMPERE80",
    "sm_86": "AMPERE86",
    "sm_87": "AMPERE87",
    "sm_89": "ADA89",
    "sm_90": "HOPPER90",
}

CUDA_ARCH_FLAG_ERROR = (
    "--config=gpu requires --//:cuda_arch=sm_XX " +
    "(see the GPU build section of docs/user/Bazel.md)."
)

CUDA_TOOLKIT_COPTS = [
    "-xcuda",
    "--cuda-path=" + CUDA_PATH,
    "-isystem",
    CUDA_PATH + "/include/cccl",
    "-Wno-unknown-cuda-version",
    "-D_ALLOW_UNSUPPORTED_LIBCPP",
    "-fopenmp",
]

CUDA_ARCH_COPTS = select(
    {
        Label("//:cuda_arch_" + arch): ["--cuda-gpu-arch=" + arch]
        for arch in CUDA_ARCHS
    },
    no_match_error = CUDA_ARCH_FLAG_ERROR,
)

CUDA_COPTS = CUDA_TOOLKIT_COPTS + CUDA_ARCH_COPTS + [
    "-ffp-contract=off",
    # Preserve Boost empty-base optimization under __CUDACC__ to match -xc++ ABI.
    "-DBOOST_DETAIL_EMPTY_VALUE_BASE",
    # Requires //bazel/gpu:cuda_placement_new.h in additional_compiler_inputs.
    "-include",
    "$(location //bazel/gpu:cuda_placement_new.h)",
]
