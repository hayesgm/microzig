const std = @import("std");
const microzig = @import("microzig/build-internals");

const Self = @This();

chips: struct {
    qn9090: *const microzig.Target,
},

boards: struct {},

pub fn init(dep: *std.Build.Dependency) Self {
    const b = dep.builder;

    const chip_qn9090: microzig.Target = .{
        .dep = dep,
        .preferred_binary_format = .elf,
        .zig_target = .{
            .cpu_arch  = .thumb,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
            .os_tag    = .freestanding,
            .abi       = .eabi,
        },
        .chip = .{
            .name = "QN9090",
            .register_definition = .{ .svd = b.path("src/chips/QN9090.xml") },
            // --- MEMORY MAP ----------------------------------------------------
            .memory_regions = &.{
                // 640 KB on-chip flash 0x0000_0000 – 0x0009_FFFF
                .{ .tag = .flash, .offset = 0x0000_0000, .length = 640 * 1024, .access = .rx },
                // 152 KB contiguous SRAM 0x0400_0000 – 0x0402_5FFF
                // (split over two AHB ports internally, but contiguous in address space)
                .{ .tag = .ram,   .offset = 0x0400_0000, .length = 152 * 1024, .access = .rw },
            },
            // -------------------------------------------------------------------
        },
        .patch_elf = nxp_crc_patch_elf,
    };

    return .{
        .chips = .{
            .qn9090 = chip_qn9090.derive(.{}),
        },
        .boards = .{},
    };
}

pub fn build(b: *std.Build) void {
    const nxp_crc_patch_elf_exe = b.addExecutable(.{
        .name = "qn90xx-patchelf",
        .root_source_file = b.path("src/tools/patchelf.zig"),
        .target = b.graph.host,
    });
    b.installArtifact(nxp_crc_patch_elf_exe);
}

/// Patch an ELF file to add a checksum over the first 8 words so the
/// cpu will properly boot.
fn nxp_crc_patch_elf(dep: *std.Build.Dependency, input: std.Build.LazyPath) std.Build.LazyPath {
    const patch_elf_exe = dep.artifact("qn90xx-patchelf");
    const run = dep.builder.addRunArtifact(patch_elf_exe);
    run.addFileArg(input);
    return run.addOutputFileArg("output.elf");
}
