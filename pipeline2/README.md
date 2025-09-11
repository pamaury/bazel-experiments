# Idea:

# We define the pipeline entry rule, e.g.
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
            allow_single_file = True,
        ),
        "hdr": pipeline_attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "dep": pipeline_attr.label(
            mandatory = True,
        ),
        "key": pipeline_attr.string(
            mandatory = True,
        ),
        "stage": pipeline_attr.string(
            mandatory = True,
        ),
    },
    # Transition to a target platform.
    cfg = riscv32_transition,
)

# When we use it:
opentitan_binary(
    name = "ot_binary",
    src = "main.c",
    hdr = "main.h",
    dep = ":dep",
    key = "ds98d7r8u34h",
)

# This expands (via a macro) to:
# Advantage: we can easily keep all attributes and so on. This rule creates a provider containing
# all the data that a normal rule would receive
opentitan_binary_pipeline_attrs(
    name = "ot_binary_attrs",
    src = "main.c",
    hdr = "main.h",
    dep = ":dep",
    key = "ds98d7r8u34h",
)
# ... and ...
opentitan_binary_rule(
    name = "ot_binary",
    pipeline_attrs = ":ot_binary_attrs",
    # And here possibly some non-pipeline attributes
)

# Internally, we have defined somewhere a label flag
label_flag(
    name = "pipeline_label_flag",
    build_setting_default = ":empty_label",
)
# Internally, opentitan_binary_rule applies the following transition to every attribute with a `pipeline = True` argument:
def _opentitan_binary_pipeline_enter_transition_impl(settings, attr):
  return {"//path/to/pipeline_label_flag": str(Label(attr.pipeline_attrs))}
opentitan_binary_pipeline_enter_transition = transition(
    implementation = _opentitan_binary_pipeline_enter_transition_impl,
    inputs = [],
    ouputs = ["//path/to/pipeline_label_flag"],
)
# What does this do? Now now `pipeline_label_flag` is pointing to `ot_binary_attrs` which means
# that every pipeline rule can now simply depend on `//path/to/pipeline_label_flag` and access all attributes.
# Advantage 1: no more fiddling with label_list_flag emulation and so on, we can directly access the target/strings/bool
# as in normal rule.
# Advantage 2: there is a single, FIXED, target to transition on.
#
# In particular, we can now define `opentitan_binary_pipeline_attrs` with an incoming transition which resets the label_flag
# to avoid propagattion:
def _opentitan_binary_pipeline_enter_transition_impl(settings, attr):
  return {"//path/to/pipeline_label_flag": "empty_label}
opentitan_binary_pipeline_leave_transition = transition(
    implementation = _opentitan_binary_pipeline_leave_transition_impl,
    inputs = [],
    ouputs = ["//path/to/pipeline_label_flag"],
)
# ...
opentitan_binary_pipeline_attrs = rule(
    ## ...
    cfg = opentitan_binary_pipeline_leave_transition,
)
# NOTE: this is convenient because this is a custom rule so adding a transition here will not clash
# with any transition that the user would like to add.
#
# Still on problem: in addition to that, every pipeline rule needs to apply `opentitan_binary_pipeline_leave_transition`
# on every non-pipeline attribute. This is to ensure that the build graph does not explode too much with useful duplicates.
# This COULD interfere with other transitions that we need. Example:
my_pipeline_rule = pipeline_rule(
    ## ...
    attrs = {
        "_my_tool": attr.label(
            default = "//path/to/my/tool",
            executable = True,
            # PROBLEM: here we want 'exec' + opentitan_binary_pipeline_leave_transition
            cfg = 'exec',
        ),
    },
)
# Solutions: this only concerns pipeline_rules so we have total control over them. There
# are two types of transitions:
# - 'exec' transitions: we can create an exec+opentitan_binary_pipeline_leave_transition transition manually
# - custom transitions: we can wrap them in a `pipeline_transition` macro which combines the two transitions.