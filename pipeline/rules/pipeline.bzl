# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

def _create_attr_func(type, attr_func, trans_func):
    def create_func(flag = None, pipeline = False, **kwargs):
        return struct(
            type = type,
            flag = str(Label(flag)) if flag else None,
            pipeline = pipeline,
            attr_args = kwargs,
            attr_func = attr_func,
            trans_func = trans_func,
        )
    return create_func

pipeline_attr = struct(
    label = _create_attr_func("label", attr.label, lambda x: x),
    string = _create_attr_func("string", attr.string, lambda x: x),
)

def pipeline_entry_rule(
    implementation,
    attrs,
    **kwargs,
):
    def transition_pipeline_impl(settings, target_attrs):
        return {
            attr.flag: attr.trans_func(getattr(target_attrs, name))
            for (name, attr) in attrs.items()
            if attr.flag
        }
    transition_pipeline = transition(
        implementation = transition_pipeline_impl,
        inputs = [],
        outputs = [attr.flag for attr in attrs.values() if attr.flag],
    )

    new_attrs = {}
    for (name, attr) in attrs.items():
        # Since we will add a transition to set the arguments,
        # we would need to either compose them (see https://github.com/bazelbuild/bazel/discussions/22019)
        # or create an indirection to apply two transitions.
        args = attr.attr_args
        if attr.pipeline:
            if 'cfg' in attr.attr_args:
                fail("transitions are not yet supported for pipeline attributes")
            args['cfg'] = transition_pipeline
        new_attrs[name] = attr.attr_func(**args)
    return rule(
        implementation = implementation,
        attrs = new_attrs,
        **kwargs
    )
