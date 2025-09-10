_PipelineAttrsInfo = provider()

def _empty_attrs_impl(ctx):
    return [DefaultInfo(), _PipelineAttrsInfo()]

empty_attrs = rule(
    implementation = _empty_attrs_impl,
    doc = "Helper function to create a target returning an empty set of attributes, for use by default in the label_flag",
)

# Attribute handling

def _create_pipeline_attr(type, kwargs):
    return struct(
        __this_is_pipeline_attr = True,
        type = type,
        kwargs = kwargs,
    )

def _is_pipeline_attr(pattr):
    return type(pattr) == "struct" and hasattr(pattr, "__this_is_pipeline_attr")

def _pipeline_label(**kwargs):
    return _create_pipeline_attr(
        type = "label",
        kwargs = kwargs,
    )

def _pipeline_label_list(**kwargs):
    return _create_pipeline_attr(
        type = "label_list",
        kwargs = kwargs,
    )

def _pipeline_string(**kwargs):
    return _create_pipeline_attr(
        type = "string",
        kwargs = kwargs,
    )

def _pipeline_attr_to_attr(attr_name, pattr):
    if not _is_pipeline_attr(pattr):
        fail("attribute '{}' was not created by a pipeline_attr function".format(attr_name))
    if pattr.type == "label_list":
        return attr.label_list(**pattr.kwargs)
    elif pattr.type == "label":
        return attr.label(**pattr.kwargs)
    elif pattr.type == "string":
        return attr.string(**pattr.kwargs)
    else:
        fail("internal error")

pipeline_attr = struct(
    label = _pipeline_label,
    label_list = _pipeline_label_list,
    string = _pipeline_string,
)

# Entry rule
def _check_pipeline_attrs(fnname, attrs, allow_pipeline = True):
    for (name, attr) in attrs.items():
        if not _is_pipeline_attr(attr):
            fail("attribute '{}' given to {} was not created by a pipeline_attr function".format(name, fnname))
        if "pipeline" in attr.kwargs and not allow_pipeline:
            fail("attribute '{}' given to {} is not allowed to have the `pipeline` attribute set".format(name, fnname))

def _check_no_intersect(fnname, attrs, pip_attrs):
    for key in attrs:
        if key in pip_attrs:
            fail("{} has both an attribute and pipeline attribute named {}: names must be unique".format(fnname, key))

_STORED_ATTR_NAME = "stored_attrs"

def _store_args_transition_impl(setting, attr):
    return {
        "//rules/pipeline:attrs": str(getattr(attr, _STORED_ATTR_NAME)),
    }

_store_args_transition = transition(
    implementation = _store_args_transition_impl,
    inputs = [],
    outputs = ["//rules/pipeline:attrs"],
)

def _clear_args_transition_impl(setting, attr):
    return {
        "//rules/pipeline:attrs": "//rules/pipeline:empty_attrs",
    }

_clear_args_transition = transition(
    implementation = _clear_args_transition_impl,
    inputs = [],
    outputs = ["//rules/pipeline:attrs"],
)

def _clear_args_exec_transition_impl(setting, attr):
    return {
        "//rules/pipeline:attrs": "//rules/pipeline:empty_attrs",
        "//command_line_option:platforms": "@platforms//host",
    }

_clear_args_exec_transition = transition(
    implementation = _clear_args_exec_transition_impl,
    inputs = [],
    outputs = ["//rules/pipeline:attrs", "//command_line_option:platforms"],
)

_ThisTargetMustBeProducedByAPipelineRuleInfo = provider()

def _add_required_provider(kwargs):
    if "providers" not in kwargs:
        kwargs["providers"] = [_ThisTargetMustBeProducedByAPipelineRuleInfo]

def _build_pip_ctx(ctx, pip_attr_name):
    pip_attrs = getattr(ctx.attr, pip_attr_name)
    if _PipelineAttrsInfo not in pip_attrs:
        fail("{} (internal error): pipeline attribute '{}' does not have the _PipelineAttrsInfo provider".format(ctx.label, pip_attr_name))
    pip_attrs = pip_attrs[_PipelineAttrsInfo]
    if not hasattr(pip_attrs, "attr"):
        fail("it seems that you tried to directly build {} outside of the context of a pipeline. ".format(ctx.label) +
                "Only pipeline rules can depend on this target and the attribute must have the `pipeline` attribute set to True.")
    return struct(
        attr = struct(**pip_attrs.attr),
        file = struct(**pip_attrs.file),
        files = struct(**pip_attrs.files),
        executable = struct(**pip_attrs.executable),
    )

def pipeline_entry_rule(implementation, **kwargs):
    """
    Document this
    """
    attrs = kwargs.pop("attrs", {})
    _check_pipeline_attrs("pipeline_entry_rule", attrs)
    pip_attrs = kwargs.pop("pipeline_attrs", {})
    _check_pipeline_attrs("pipeline_entry_rule", pip_attrs, False)
    _check_no_intersect("pipeline_entry_rule", attrs, pip_attrs)

    cfg = kwargs.pop("cfg", None)
    if kwargs:
        fail("unsupported arguments to pipeline_entry_rule:", kwargs)

    def _store_attrs_rule_impl(ctx):
        stored_ctx = {}
        for entry in ["attr", "file", "files", "executable"]:
            entries = getattr(ctx, entry, struct())
            stored_ctx[entry] = {
                name: getattr(entries, name)
                for name in pip_attrs.keys()
                if hasattr(entries, name)
            }
        return _PipelineAttrsInfo(**stored_ctx)

    store_attrs_rule = rule(
        implementation = _store_attrs_rule_impl,
        attrs = {
            name: _pipeline_attr_to_attr(name, pattr)
            for (name, pattr) in pip_attrs.items()
        },
        cfg = _clear_args_transition,
    )

    if _STORED_ATTR_NAME in attrs:
        fail("pipeline_entry_rule cannot have an attribute named {}".format(_STORED_ATTR_NAME))

    def _entry_rule_impl(ctx):
        pip_ctx = _build_pip_ctx(ctx, _STORED_ATTR_NAME)
        return implementation(ctx, pip_ctx)

    for (key, desc) in attrs.items():
        pipeline = desc.kwargs.pop("pipeline", False)
        if pipeline:
            if "cfg" in desc.kwargs:
                fail("attribute '{}' in pipeline_entry_rule has `pipeline` set to True, ".format(key) +
                     "therefore it cannot have an outgoing transition (this limitation may be lifted in the future)")
            desc.kwargs["cfg"] = _store_args_transition
            _add_required_provider(desc.kwargs)

    entry_rule = rule(
        implementation = _entry_rule_impl,
        attrs = {
            name: _pipeline_attr_to_attr(name, pattr)
            for (name, pattr) in attrs.items()
        } | {
            _STORED_ATTR_NAME: attr.label(
                mandatory = True,
                doc = "TODO",
            )
        }
    )

    def rule_wrapper(name, **kwargs):
        # Store the attributes.
        store_kwargs = {}
        for key in pip_attrs:
            if key in kwargs:
                store_kwargs[key] = kwargs.pop(key)

        store_attrs_rule(
            name = name + "_attrs",
            **store_kwargs,
        )
        kwargs[_STORED_ATTR_NAME] = ":{}_attrs".format(name)
        # Call the actual with a pointer to the attributs.
        entry_rule(
            name = name,
            **kwargs,
        )

    return rule_wrapper, store_attrs_rule, entry_rule

def pipeline_rule(implementation, **kwargs):
    attrs = kwargs.pop("attrs", {})
    _check_pipeline_attrs("pipeline_entry_rule", attrs)
    pip_attrs = kwargs.pop("pipeline_attrs", {})
    _check_pipeline_attrs("pipeline_entry_rule", pip_attrs, False)
    _check_no_intersect("pipeline_entry_rule", attrs, pip_attrs)

    PIP_ATTR_NAME = "_pipeline_attrs"

    if PIP_ATTR_NAME in attrs:
        fail("pipeline_rule cannot have an attribute named {}".format(PIP_ATTR_NAME))

    def _rule_impl(ctx):
        pip_ctx = _build_pip_ctx(ctx, PIP_ATTR_NAME)
        providers = implementation(ctx, pip_ctx)
        if providers == None:
            providers = []
        return providers + [_ThisTargetMustBeProducedByAPipelineRuleInfo()]

    for (key, desc) in attrs.items():
        pipeline = desc.kwargs.pop("pipeline", False)
        if pipeline:
            _add_required_provider(desc.kwargs)
        else:
            cfg = desc.kwargs.get("cfg", None)
            if cfg != None and cfg != "exec":
                fail("attribute '{}' in pipeline_rule does not have `pipeline` set to True, ".format(key) +
                     "therefore it cannot have an outgoing transition other than 'exec' (this limitation may be lifted in the future)")
            if cfg == "exec":
                desc.kwargs["cfg"] = _clear_args_transition
            else:
                desc.kwargs["cfg"] = _clear_args_exec_transition

    pip_rule = rule(
        implementation = _rule_impl,
        attrs = {
            name: _pipeline_attr_to_attr(name, pattr)
            for (name, pattr) in attrs.items()
        } | {
            PIP_ATTR_NAME: attr.label(
                default = "//rules/pipeline:attrs",
                providers = [_PipelineAttrsInfo],
                doc = "TODO",
            )
        },
        **kwargs
    )
    return pip_rule
