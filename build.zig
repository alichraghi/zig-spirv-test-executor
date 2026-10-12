const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const spirv_tools_dep = b.dependency("spirv_tools", .{ .target = target, .optimize = optimize });
    const spirv_headers = b.dependency("spirv_headers", .{});
    const opencl = b.dependency("opencl", .{ .target = target, .optimize = optimize }).module("opencl");

    const vulkan = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");

    const spirv_tools = b.addTranslateC(.{
        .root_source_file = spirv_tools_dep.path("include/spirv-tools/libspirv.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const spirv = b.addTranslateC(.{
        .root_source_file = spirv_headers.path("include/spirv/unified1/spirv.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const exe = b.addExecutable(.{
        .name = "zig-spirv-test-executor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "opencl", .module = opencl },
                .{ .name = "vulkan", .module = vulkan },
                .{ .name = "spirv-tools", .module = spirv_tools },
                .{ .name = "spirv", .module = spirv },
            },
        }),
    });

    const grammar_tables = b.addSystemCommand(&.{"python3"});
    grammar_tables.addFileArg(spirv_tools_dep.path("utils/ggt.py"));
    for ([_][]const u8{ "Context.py", "IndexRange.py", "Operand.py", "StringList.py", "__init__.py" }) |name| {
        grammar_tables.addFileInput(spirv_tools_dep.path(b.fmt("utils/Table/{s}", .{name})));
    }
    grammar_tables.addArg("--spirv-core-grammar");
    grammar_tables.addFileArg(spirv_headers.path("include/spirv/unified1/spirv.core.grammar.json"));
    grammar_tables.addArg("--core-tables-header-output");

    const table_header = grammar_tables.addOutputFileArg("core_tables_header.inc");
    grammar_tables.addArg("--core-tables-body-output");

    const table_body = grammar_tables.addOutputFileArg("core_tables_body.inc");
    grammar_tables.addPrefixedFileArg("--extinst=,", spirv_headers.path(b.fmt("include/spirv/unified1/extinst.{s}.grammar.json", .{"glsl.std.450"})));
    grammar_tables.addPrefixedFileArg("--extinst=,", spirv_headers.path(b.fmt("include/spirv/unified1/extinst.{s}.grammar.json", .{"opencl.std.100"})));

    const generated = b.addWriteFiles();
    _ = generated.addCopyFile(table_header, "core_tables_header.inc");
    _ = generated.addCopyFile(table_body, "core_tables_body.inc");

    const registry = b.addSystemCommand(&.{"python3"});
    registry.addFileArg(spirv_tools_dep.path("utils/generate_registry_tables.py"));
    registry.addArg("--xml");
    registry.addFileArg(spirv_headers.path("include/spirv/spir-v.xml"));
    registry.addArg("--generator-output");
    _ = generated.addCopyFile(registry.addOutputFileArg("generators.inc"), "generators.inc");

    const spirv_validator = b.addLibrary(.{
        .name = "spirv-validator",
        .linkage = .static,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true }),
    });
    spirv_validator.root_module.addIncludePath(spirv_tools_dep.path(""));
    spirv_validator.root_module.addIncludePath(spirv_tools_dep.path("include"));
    spirv_validator.root_module.addIncludePath(spirv_headers.path("include"));
    spirv_validator.root_module.addIncludePath(spirv_headers.path("include/spirv/unified1"));
    spirv_validator.root_module.addIncludePath(generated.getDirectory());
    spirv_validator.root_module.addCSourceFiles(.{
        .root = spirv_tools_dep.path("source"),
        .files = &.{
            "util/bit_vector.cpp",                  "util/parse_number.cpp",                  "util/string_utils.cpp",
            "assembly_grammar.cpp",                 "binary.cpp",                             "diagnostic.cpp",
            "disassemble.cpp",                      "ext_inst.cpp",                           "extensions.cpp",
            "name_mapper.cpp",                      "opcode.cpp",                             "operand.cpp",
            "parsed_operand.cpp",                   "print.cpp",                              "spirv_endian.cpp",
            "spirv_target_env.cpp",                 "spirv_validator_options.cpp",            "table.cpp",
            "text.cpp",                             "text_handler.cpp",                       "table2.cpp",
            "to_string.cpp",                        "val/validate.cpp",                       "val/validate_adjacency.cpp",
            "val/validate_annotation.cpp",          "val/validate_arithmetics.cpp",           "val/validate_atomics.cpp",
            "val/validate_barriers.cpp",            "val/validate_bitwise.cpp",               "val/validate_builtins.cpp",
            "val/validate_capability.cpp",          "val/validate_cfg.cpp",                   "val/validate_composites.cpp",
            "val/validate_constants.cpp",           "val/validate_conversion.cpp",            "val/validate_debug.cpp",
            "val/validate_decorations.cpp",         "val/validate_derivatives.cpp",           "val/validate_dot_product.cpp",
            "val/validate_extensions.cpp",          "val/validate_execution_limitations.cpp", "val/validate_explicit_layout.cpp",
            "val/validate_function.cpp",            "val/validate_graph.cpp",                 "val/validate_group.cpp",
            "val/validate_id.cpp",                  "val/validate_image.cpp",                 "val/validate_interfaces.cpp",
            "val/validate_instruction.cpp",         "val/validate_layout.cpp",                "val/validate_literals.cpp",
            "val/validate_logicals.cpp",            "val/validate_logical_pointers.cpp",      "val/validate_memory.cpp",
            "val/validate_memory_semantics.cpp",    "val/validate_mesh_shading.cpp",          "val/validate_misc.cpp",
            "val/validate_mode_setting.cpp",        "val/validate_non_uniform.cpp",           "val/validate_pipe.cpp",
            "val/validate_primitives.cpp",          "val/validate_ray_query.cpp",             "val/validate_ray_tracing.cpp",
            "val/validate_ray_tracing_reorder.cpp", "val/validate_scopes.cpp",                "val/validate_small_type_uses.cpp",
            "val/validate_tensor_layout.cpp",       "val/validate_tensor.cpp",                "val/validate_type.cpp",
            "val/validate_invalid_type.cpp",        "val/basic_block.cpp",                    "val/construct.cpp",
            "val/function.cpp",                     "val/instruction.cpp",                    "val/validation_state.cpp",
        },
    });
    exe.root_module.linkLibrary(spirv_validator);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_kernel = b.addTest(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_kernel.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .spirv64,
                .os_tag = .opencl,
                .abi = .none,
                .cpu_model = .{ .explicit = &std.Target.spirv.cpu.opencl_v2 },
                .cpu_features_add = std.Target.spirv.featureSet(&.{
                    .int64,
                    .float64,
                    .generic_pointer,
                }),
            }),
            .optimize = optimize,
        }),
        .use_llvm = false,
        .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple },
    });

    const run_test = b.addRunArtifact(exe);
    run_test.addFileArg(test_kernel.getEmittedBin());
    run_test.addPassthruArgs();

    const test_step = b.step("test", "Run the test kernel");
    test_step.dependOn(&run_test.step);
}
