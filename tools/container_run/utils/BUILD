py_binary(
    name = "extract_image_id",
    srcs = [":extract_image_id.py"],
    visibility = ["//visibility:public"],
)

py_binary(
    name = "to_json",
    srcs = ["to_json.py"],
    visibility = ["//visibility:public"],
)

py_binary(
    name = "extract_last_layer",
    srcs = [":extract_last_layer.py"],
    visibility = ["//visibility:public"],
)

exports_files([
    "commit.sh.tpl",
    "image_util.sh.tpl",
    "commit_layer.sh.tpl",
])
