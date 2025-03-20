# basic RUN instruction implementation for rules_oci

Blog: https://narang99.github.io/2025-03-20-bazel-docker-run/

If you want to use `container_run_and_commit` from `rules_docker` or the `RUN` instruction while using `rules_oci`, you can try using this implementation. Its a very simple implementation with the following constraints:

- The rule is not hermetic (`RUN` is inherently not, which is why `rules_oci` did not include this)
- It can be slow on large docker images (we do docker load and save, which can be costly for big images)

# Installation

I've not added support for standard installation methods (MODULE.bazel or WORKSPACE). Just clone this repository and copy the rules in a location in your monorepo  


```bash
git clone git@github.com:narang99/oci_container_run_and_commit.git
cd oci_container_run_and_commit

# copy the rules to tools/container_run in your monorepo, the hardcoded relative path is intentional and required
cp -R oci_container_run_and_commit/tools/container_run <your-monorepo>/tools/container_run
```

# Usage


The code below would:
- use `:base_nginx` as a base image (this should be of type `oci_image`)
- run a container using the base image
- run `commands` in the container as `sh -c 'curl https://github.com/my-cool-nginx-conf -o /etc/nginx/nginx.conf && echo 'using my cool conf''`
- commit the container and extract the last layer
- create a new target of type `oci_image` of name `nginx_with_conf_from_internet` with `:base_nginx` as base image and overlay the last layer on top of this base


```python
load("//tools/container_run:defs.bzl", "oci_run_and_commit")


oci_run_and_commit(
    name="nginx_with_conf_from_internet",
    # a target of type `oci_image`
    base=":base_nginx",
    commands=[
        "curl https://github.com/my-cool-nginx-conf -o /etc/nginx/nginx.conf",
        "echo 'using my cool conf'"
    ],
    visibility=["//visibility:public"],
    entrypoint=["nginx"],
)
```


Approximately similar to creating a `Dockerfile` with the content below
```Dockerfile
# actual docker image referenced by :base_nginx
FROM nginx

RUN curl https://github.com/my-cool-nginx-conf -o /etc/nginx/nginx.conf && echo 'using my cool conf'
```
And docker building this `Dockerfile`
