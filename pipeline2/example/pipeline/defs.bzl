load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("@rules_cc//cc:action_names.bzl", "OBJ_COPY_ACTION_NAME")
load("//rules/pipeline:pipeline.bzl", "pipeline_entry_rule", "pipeline_rule", "pipeline_attr")

# Building rule
#
# This rule is responsible for compiling and linking the binary.

def _build_binary_impl(ctx, pip_ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    features = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    compilation_contexts = [
        dep[CcInfo].compilation_context
        for dep in pip_ctx.attr.deps
    ]

    name = ctx.label.name
    all_srcs = pip_ctx.files.srcs + pip_ctx.files.hdrs

    # cc_common.compile crashes if a header file is passed to srcs, so filter
    # those out and passed them as private headers instead
    hdrs = [s for s in all_srcs if s.extension == "h"]
    srcs = [s for s in all_srcs if s.extension != "h"]
    cctx, cout = cc_common.compile(
        name = name,
        actions = ctx.actions,
        feature_configuration = features,
        cc_toolchain = cc_toolchain,
        compilation_contexts = compilation_contexts,
        srcs = srcs,
        private_hdrs = hdrs,
        user_compile_flags = ["-ffreestanding"],
        defines = [],
        local_defines = [],
    )

    linking_contexts = [
        dep[CcInfo].linking_context
        for dep in pip_ctx.attr.deps
    ]

    lout = cc_common.link(
        name = name + ".elf",
        actions = ctx.actions,
        feature_configuration = features,
        cc_toolchain = cc_toolchain,
        compilation_outputs = cout,
        linking_contexts = linking_contexts,
    )
    return [DefaultInfo(files = depset([lout.executable]))]

BUILD_BINARY_ATTRS = {
    "srcs": pipeline_attr.label_list(
        allow_files = True,
        default = []
    ),
    "hdrs": pipeline_attr.label_list(
        allow_files = True,
        default = []
    ),
    "deps": pipeline_attr.label_list(default = []),
}

build_binary = pipeline_rule(
    implementation = _build_binary_impl,
    pipeline_attrs = BUILD_BINARY_ATTRS,
    fragments = ["cpp"],
    toolchains = ["@rules_cc//cc:toolchain_type"],
)

# Signing rule.
#
# This rule takes as input an ELF binary and signs it.
def _sign_binary(ctx, pip_ctx):
    out_binary = ctx.actions.declare_file(ctx.label.name)

    ctx.actions.run(
        executable = ctx.executable._tool,
        inputs = [ctx.file.binary],
        outputs = [out_binary],
        arguments = [
            ctx.file.binary.path,
            pip_ctx.attr.key,
            out_binary.path,
        ]
    )

    return [DefaultInfo(files = depset([out_binary]))]

SIGN_BINARY_ATTRS = {
    "key": pipeline_attr.string(
        mandatory = True,
    ),
}

sign_binary = pipeline_rule(
    implementation = _sign_binary,
    attrs = {
        "binary": pipeline_attr.label(
            mandatory = True,
            allow_single_file = True,
            # Forward pipeline attributes.
            pipeline = True,
        ),
        "_tool": pipeline_attr.label(
            default = "//example/pipeline:sign_binary_tool",
            executable = True,
            cfg = "exec",
        )
    },
    pipeline_attrs = SIGN_BINARY_ATTRS,
)

# Transition to our platform so we can build for RISCV32.
def _riscv32_transition_impl(settings, attr):
    return {
        "//command_line_option:platforms": "//toolchain:opentitan_platform",
    }

riscv32_transition = transition(
    implementation = _riscv32_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
    ],
)

def _opentitan_binary_impl(ctx, pip_ctx):
    # Simply forward the built binary.
    binary_files = ctx.attr._binary[0][DefaultInfo]
    return [DefaultInfo(
        files = binary_files.files,
    )]

# We define the pipeline entry rule. Only the first value is useful but due
# to a technical limitation of bazel, the other return values need to be named.
opentitan_binary, _ot_binary_store_rule, _ot_binary_entry_rule = pipeline_entry_rule(
    implementation = _opentitan_binary_impl,
    attrs = {
        "_binary": pipeline_attr.label(
            default = "//example/pipeline:signed_elf_binary",
            # Forward pipeline attribute down the transition.
            pipeline = True,
        ),
    },
    pipeline_attrs = BUILD_BINARY_ATTRS | SIGN_BINARY_ATTRS,
    # Transition to a target platform.
    cfg = riscv32_transition,
)
