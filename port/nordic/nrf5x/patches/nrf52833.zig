// patches/nrf52833.zig
const Patch = @import("microzig/build-internals").Patch;

/// Common enum definitions for both GPIO ports (P0, P1).
fn gpioPatches(comptime port: []const u8) []const Patch {
    return &.{
        // -------- Pull enum -------------------------------------------------
        .{
            .add_enum = .{
                .parent = "types.peripherals." ++ port,
                .@"enum" = .{
                    .name = "Pull",
                    .bitsize = 2,
                    .fields = &.{
                        .{ .value = 0b00, .name = "Disabled"  }, // no pull
                        .{ .value = 0b01, .name = "PullDown"  },
                        .{ .value = 0b11, .name = "PullUp"    },
                    },
                },
            },
        },
        .{
            .set_enum_type = .{
                .of = "types.peripherals." ++ port ++ ".PIN_CNF.PULL",
                .to = "types.peripherals." ++ port ++ ".Pull",
            },
        },

        // -------- Drive enum ------------------------------------------------
        .{
            .add_enum = .{
                .parent = "types.peripherals." ++ port,
                .@"enum" = .{
                    .name = "Drive",
                    .bitsize = 3,
                    .fields = &.{
                        //  “S” = Standard; “H” = High; “D” = Disconnect
                        .{ .value = 0b000, .name = "S0S1" },
                        .{ .value = 0b001, .name = "H0S1" },
                        .{ .value = 0b010, .name = "S0H1" },
                        .{ .value = 0b011, .name = "H0H1" },
                        .{ .value = 0b100, .name = "D0S1" },
                        .{ .value = 0b101, .name = "D0H1" },
                        .{ .value = 0b110, .name = "S0D1" },
                        .{ .value = 0b111, .name = "H0D1" },
                    },
                },
            },
        },
        .{
            .set_enum_type = .{
                .of = "types.peripherals." ++ port ++ ".PIN_CNF.DRIVE",
                .to = "types.peripherals." ++ port ++ ".Drive",
            },
        },
    };
}

/// Export the combined patch list for P0 and P1.
pub const patches: []const Patch = &.{
    gpioPatches("P0") ++ gpioPatches("P1"),
};
