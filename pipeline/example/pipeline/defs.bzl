load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("@rules_cc//cc:action_names.bzl", "OBJ_COPY_ACTION_NAME")
load("//rules:pipeline.bzl",
    "pipeline_attr",
    "pipeline_entry_rule",
)
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _sign_binary(ctx):
    out_binary = ctx.actions.declare_file(ctx.label.name)
    key = ctx.attr.key[BuildSettingInfo].value

    ctx.actions.run(
        executable = ctx.executable._tool,
        inputs = [ctx.file.binary],
        outputs = [out_binary],
        arguments = [
            ctx.file.binary.path,
            key,
            out_binary.path,
        ]
    )

    return [DefaultInfo(files = depset([out_binary]))]

sign_binary = rule(
    implementation = _sign_binary,
    attrs = {
        "binary": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "key": attr.label(
            mandatory = True,
        ),
        "_tool": attr.label(
            default = "//example/pipeline:sign_binary_tool",
            executable = True,
            cfg = "host",
        )
    },
)

def _opentitan_binary_impl(ctx):
    binary_files = ctx.attr._binary[0][DefaultInfo]
    return [DefaultInfo(
        files = binary_files.files,
    )]

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

opentitan_binary = pipeline_entry_rule(
    implementation = _opentitan_binary_impl,
    attrs = {
        "_binary": pipeline_attr.label(
            default = "//example/pipeline:signed_binary",
            # Forward pipeline attribute down the transition.
            pipeline = True,
        ),
        "src": pipeline_attr.label(
            mandatory = True,
            flag = "//example/pipeline:cc_binary_src",
            allow_single_file = True,
        ),
        "hdr": pipeline_attr.label(
            mandatory = True,
            flag = "//example/pipeline:cc_binary_hdr",
            allow_single_file = True,
        ),
        "dep": pipeline_attr.label(
            mandatory = True,
            flag = "//example/pipeline:cc_binary_dep",
        ),
        "key": pipeline_attr.string(
            mandatory = True,
            flag = "//example/pipeline:sign_key",
        ),
    },
    # Transition to a target platform.
    cfg = riscv32_transition,
)
