load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")
load("//rules:pipeline.bzl",
    "pipeline_attr",
    "pipeline_entry_rule",
)
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _sign_binary(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    out_binary = ctx.actions.declare_file(ctx.label.name)
    sign_file = ctx.actions.declare_file(ctx.label.name + ".key")

    key = ctx.attr.key[BuildSettingInfo].value
    ctx.actions.write(sign_file, "the key is: {}".format(key))

    ctx.actions.run(
        executable = cc_toolchain.objcopy_executable,
        inputs = [ctx.file.binary, sign_file],
        outputs = [out_binary],
        arguments = [
            "--add-section",
            ".ot.key={}".format(sign_file.path),
            "--set-section-flags",
            ".ot.key=noload,readonly",
            ctx.file.binary.path,
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
    },
    toolchains = ["@rules_cc//cc:toolchain_type"],
)

def _opentitan_binary_impl(ctx):
    binary_files = ctx.attr._binary[0][DefaultInfo]
    return [DefaultInfo(
        files = binary_files.files,
    )]

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
        "key": pipeline_attr.string(
            mandatory = True,
            flag = "//example/pipeline:sign_key",
        ),
    }
)
