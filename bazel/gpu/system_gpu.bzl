# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, The OpenROAD Authors

"""Repository rule wrapping the host CUDA toolkit for --config=gpu."""

_CUDA_LOCAL_BUILD = """\
load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "compiler_inputs",
    srcs = glob(
        [
            "bin/fatbinary",
            "bin/ptxas",
            "include/**",
            "nvvm/**",
            "version.json",
        ],
        allow_empty = True,
    ),
)

# Links against the driver stub; the real libcuda.so.1 is found at runtime.
cc_library(
    name = "cudart",
    additional_linker_inputs = glob([
        "{libdir}/libcudart.so*",
        "{libdir}/stubs/libcuda.so*",
    ]),
    linkopts = [
        "-L{ws_root}/{libdir}",
        "-Wl,-rpath,{rpath_dir}",
        "-lcudart",
        "-L{ws_root}/{libdir}/stubs",
        "-lcuda",
    ],
)

cc_library(
    name = "cufft",
    additional_linker_inputs = glob(["{libdir}/libcufft.so*"]),
    linkopts = [
        "-L{ws_root}/{libdir}",
        "-lcufft",
    ],
    deps = [":cudart"],
)
"""

_STUB_BUILD = """\
load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

_FAIL = select({{"@platforms//:incompatible": []}}, no_match_error = {message})

filegroup(name = "compiler_inputs", srcs = _FAIL)
cc_library(name = "cudart", srcs = _FAIL)
cc_library(name = "cufft", srcs = _FAIL)
"""

def _prefix_problem(rctx, where, root, libdir):
    if not rctx.path(root).exists:
        return where + " does not exist"
    for rel in [
        "include/cuda.h",
        "bin/ptxas",
        "nvvm/libdevice",
        libdir + "/libcudart.so",
        libdir + "/libcufft.so",
        libdir + "/stubs/libcuda.so",
    ]:
        if not rctx.path(root + "/" + rel).exists:
            return where + " is missing " + rel
    return None

def _cuda_local_repository_impl(rctx):
    env_value = rctx.getenv("OPENROAD_CUDA_PATH")
    explicit = env_value != None
    root = env_value if explicit else rctx.attr.default_path
    where = (
        "OPENROAD_CUDA_PATH=" + root if explicit else "default path " + root + " (OPENROAD_CUDA_PATH is unset)"
    )

    if explicit and not env_value.strip():
        problem = "OPENROAD_CUDA_PATH is set but empty"
        libdir = "lib64"
    else:
        libdir = "lib64" if rctx.path(root + "/lib64").exists else "lib"
        problem = _prefix_problem(rctx, where, root, libdir)

    if problem != None:
        message = (
            "GPU build is not usable: " + problem + ". Point OPENROAD_CUDA_PATH " +
            "at a full CUDA toolkit containing bin/ptxas, nvvm/libdevice, " +
            "libcudart, libcufft, and libcuda stub."
        )
        rctx.file("BUILD.bazel", _STUB_BUILD.format(message = repr(message)))
    else:
        for entry in ["include", "lib", "lib64", "bin", "nvvm", "version.json"]:
            entry_path = rctx.path(root + "/" + entry)
            if entry_path.exists:
                rctx.symlink(entry_path.realpath, entry)
        rctx.file(
            "BUILD.bazel",
            _CUDA_LOCAL_BUILD.format(
                rpath_dir = root + "/" + libdir,
                ws_root = "external/" + rctx.name,
                libdir = libdir,
            ),
        )

cuda_local_repository = repository_rule(
    implementation = _cuda_local_repository_impl,
    local = True,
    environ = ["OPENROAD_CUDA_PATH"],
    attrs = {"default_path": attr.string(mandatory = True)},
)
