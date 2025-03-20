# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Rules to run a command inside a container, and either commit the result
to new container image, or extract specified targets to a directory on
the host machine.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
# load(
#     "//skylib:hash.bzl",
#     _hash_tools = "tools",
# )

def _commit_layer_impl(
        ctx,
        name = None,
        image = None,
        commands = None,
        env = None,
        output_layer_tar = None):
    """Implementation for the container_run_and_commit_layer rule.

    This rule runs a set of commands in a given image, waits for the commands
    to finish, and then extracts the layer of changes into a new container_layer target.

    Args:
        ctx: The bazel rule context
        name: A unique name for this rule.
        image: The input image tarball
        commands: The commands to run in the input image container
        env: str Dict, overrides ctx.attr.env
        output_layer_tar: The output layer obtained as a result of running
                          the commands on the input image
    """

    name = name or ctx.attr.name
    image = image or ctx.file.image
    commands = commands or ctx.attr.commands
    env = env or ctx.attr.env
    script = ctx.actions.declare_file(name + ".build")
    output_layer_tar = output_layer_tar or ctx.outputs.layer

    # Generate a shell script to execute the reset cmd
    image_utils = ctx.actions.declare_file("image_util.sh")
    ctx.actions.expand_template(
        template = ctx.file._image_utils_tpl,
        output = image_utils,
        # removed substitutions because we rely on system docker now, no fancy toochaining for now
        substitutions = {
            # "%{docker_flags}": " ".join(toolchain_info.docker_flags),
            # "%{docker_tool_path}": docker_path(toolchain_info),
        },
        is_executable = True,
    )

    docker_env = [
        "{}={}".format(
            ctx.expand_make_variables("env", key, {}),
            ctx.expand_make_variables("env", value, {}),
        )
        for key, value in env.items()
    ]

    env_file = ctx.actions.declare_file(name + ".env")
    ctx.actions.write(env_file, "\n".join(docker_env))

    output_diff_id = ctx.actions.declare_file(output_layer_tar.basename + ".sha256")

    # Generate a shell script to execute the run statement and extract the layer
    ctx.actions.expand_template(
        template = ctx.file._run_tpl,
        output = script,
        substitutions = {
            "%{commands}": _process_commands(commands),
            "%{env_file_path}": env_file.path,
            "%{image_id_extractor_path}": ctx.executable._extract_image_id.path,
            "%{image_last_layer_extractor_path}": ctx.executable._last_layer_extractor_tool.path,
            "%{image_tar}": image.path,
            "%{output_diff_id}": output_diff_id.path,
            "%{output_image}": "bazel/%s:%s" % (
                ctx.label.package or "default",
                name,
            ),
            "%{output_layer_tar}": output_layer_tar.path,
            "%{util_script}": image_utils.path,
        },
        is_executable = True,
    )

    runfiles = [image, image_utils, env_file]

    ctx.actions.run(
        outputs = [output_layer_tar, output_diff_id],
        inputs = runfiles,
        executable = script,
        mnemonic = "RunAndCommitLayer",
        tools = [ctx.executable._extract_image_id, ctx.executable._last_layer_extractor_tool],
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(files = depset([output_layer_tar])),
    ]

_commit_layer_attrs = dicts.add({
    "commands": attr.string_list(
        doc = "A list of commands to run (sequentially) in the container.",
        mandatory = True,
        allow_empty = False,
    ),
    "env": attr.string_dict(),
    "image": attr.label(
        doc = "The image to run the commands in.",
        mandatory = True,
        allow_single_file = True,
        cfg = "target",
    ),
    "_extract_image_id": attr.label(
        default = Label("//tools/container_run/utils:extract_image_id"),
        cfg = "exec",
        executable = True,
        allow_files = True,
    ),
    "_image_utils_tpl": attr.label(
        default = Label("//tools/container_run/utils:image_util.sh.tpl"),
        allow_single_file = True,
    ),
    "_last_layer_extractor_tool": attr.label(
        default = Label("//tools/container_run/utils:extract_last_layer"),
        cfg = "exec",
        executable = True,
        allow_files = True,
    ),
    "_run_tpl": attr.label(
        default = Label("//tools/container_run/utils:commit_layer.sh.tpl"),
        allow_single_file = True,
    ),
})

_commit_layer_outputs = {
    "layer": "%{name}-layer.tar",
}

container_run_and_commit_layer = rule(
    attrs = _commit_layer_attrs,
    doc = ("This rule runs a set of commands in a given image, waits" +
           "for the commands to finish, and then commits the" +
           "container state to a new layer."),
    executable = False,
    outputs = _commit_layer_outputs,
    implementation = _commit_layer_impl,
)

def _process_commands(command_list):
    # Use the $ to allow escape characters in string
    return '"sh -c \'{0}\'"'.format(" && ".join(command_list))
