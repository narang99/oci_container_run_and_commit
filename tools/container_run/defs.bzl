load(":run.bzl", "container_run_and_commit_layer")
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_push", "oci_load")

def oci_run_and_commit(name, base, commands, **kwargs):
    """Equivalent of the `container_run_and_commit` rule in rules_docker

    This is a very basic port which works with rules_oci, it generates a target with `name` of type oci_image
    which is created by running `commands` from base image `base`
    This rule relies on `docker` being present and installed in the system path

    Args:
        name: name of the final oci_image target to be created
        base: label of type oci_image, the base image to run the commands on
        commands: list of strings, commands to run in the container (should be somewhat like a list passed to RUN in Dockerfile)
        kwargs: kwargs for the final `oci_image` target, passed as is (you cannot however pass `tars` as a kwarg)

    The rule translates to running this command:

    If your commands are `["echo hello world", "ls /"]`
    ```
    docker run <base-image-loaded-to-daemon> "sh -c "echo hello world && ls /"'
    ```

    This function is not as powerful as `container_layer` + `container_run_and_commit` combinations of `rules_docker`
    You can't put this rule randomly between `pkg_tar` invocations, it HAS to be an `oci_image`

    This means you cannot interleave RUN instructions in your build process
    A general strategy you can use is:
    - Use rules to build base image from dockerfile to do all RUN instructions (pre bazel calls)
    - use bazel to build your application and add layers to the base image
    - use this rule to add layers to the built image (post bazel calls)

    NOTE: the performance of using run-and-commit will most likely be very bad, it loads your docker image in the daemon, which can be a costly operation for huge images. Use it as a last resort
    Since the rule is also used in the "end" of your image generation and would run every time your image changes, cache hits would generally be bad
    """
    load_name = "{name}_base_load".format(name=name)
    oci_load(
        name = load_name,
        image = base,
        repo_tags = ["{load_name}:latest".format(load_name=load_name)],
    )

    tar_name = "{name}_base_tar".format(name=name)
    native.filegroup(
        name = tar_name,
        srcs = [":{load_name}".format(load_name=load_name)],
        output_group = "tarball",
    )

    commit_layer_name = "{name}_commit_layer".format(name=name)
    container_run_and_commit_layer(
        name = commit_layer_name,
        image = ":{tar_name}".format(tar_name=tar_name),
        commands = commands,
    )

    if "tars" in kwargs:
      fail("passing `tars` to kwargs is not valid, use other oci_image options")

    oci_image(
        name = name,
        base = base,
        tars = [":{commit_layer_name}".format(commit_layer_name=commit_layer_name)],
        **kwargs,
    )
