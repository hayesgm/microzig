const std = @import("std");

// QN9090 boot header constants (matching Python script)
const IMAGE_HEADER_MARKER = 0x98447902;
const BOOT_BLOCK_MARKER = 0xBB0110BB;

pub fn main() !u8 {
    const allocator = std.heap.page_allocator;
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len != 3) {
        std.log.err("usage: qn90xx-patchelf <input> <output>", .{});
        return 1;
    }

    const input_file_name = argv[1];
    const output_file_name = argv[2];

    // The Python script's approach:
    // 1. Copy input to output
    // 2. Parse sections using objdump
    // 3. Patch header in the output file
    // 4. Dump last section, append boot block, update section

    // First copy input to output
    if (!std.mem.eql(u8, input_file_name, output_file_name)) {
        try std.fs.cwd().copyFile(input_file_name, std.fs.cwd(), output_file_name, .{});
    }

    // Parse sections using objdump (like Python script does)
    const sections_cmd = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "arm-none-eabi-objdump", "-h", output_file_name },
    });
    defer allocator.free(sections_cmd.stdout);
    defer allocator.free(sections_cmd.stderr);

    if (sections_cmd.term.Exited != 0) {
        std.log.err("objdump failed: {s}", .{sections_cmd.stderr});
        return 1;
    }

    // Parse sections to find first and last LOAD sections
    var first_section: ?Section = null;
    var last_section: ?Section = null;
    
    // The objdump format has section info on one line and flags on the next
    var lines = std.mem.splitScalar(u8, sections_cmd.stdout, '\n');
    
    while (lines.next()) |line| {
        // Skip empty lines and lines that don't start with a number
        if (line.len < 3) continue;
        
        // Check if this is a section header line (starts with index)
        const trimmed = std.mem.trim(u8, line, " ");
        if (trimmed.len == 0) continue;
        
        // Section lines start with a number (possibly with leading spaces)
        const first_char = trimmed[0];
        if (!std.ascii.isDigit(first_char)) continue;
        
        // Parse the section info
        var tokens = std.mem.tokenizeAny(u8, trimmed, " \t");
        
        _ = tokens.next() orelse continue; // idx
        const name = tokens.next() orelse continue;
        const size_str = tokens.next() orelse continue;
        _ = tokens.next() orelse continue; // vma
        const lma_str = tokens.next() orelse continue;
        const offset_str = tokens.next() orelse continue;
        
        // Parse numeric values
        const size = std.fmt.parseInt(u32, size_str, 16) catch continue;
        const lma = std.fmt.parseInt(u32, lma_str, 16) catch continue;
        const offset = std.fmt.parseInt(u32, offset_str, 16) catch continue;
        
        // Skip empty sections
        if (size == 0) continue;
        
        // Check next line for flags
        const next_line = lines.next() orelse continue;
        if (std.mem.indexOf(u8, next_line, "LOAD") == null) continue;
        
        // This is a LOAD section
        const section = Section{
            .name = try allocator.dupe(u8, name),
            .size = size,
            .lma = lma,
            .offset = offset,
        };
        
        if (first_section == null or lma < first_section.?.lma) {
            if (first_section) |s| allocator.free(s.name);
            first_section = section;
        } else if (last_section == null or lma > last_section.?.lma) {
            if (last_section) |s| allocator.free(s.name);
            last_section = section;
        } else {
            allocator.free(section.name);
        }
    }
    defer if (first_section) |s| allocator.free(s.name);
    defer if (last_section) |s| allocator.free(s.name);

    if (first_section == null or last_section == null) {
        std.log.err("Could not find LOAD sections", .{});
        return 1;
    }

    // Constants (matching Python defaults)
    const image_addr: u32 = 0x00000000;
    const stated_size: u32 = 0x80000; // 512KB from linker script

    // Calculate boot block offset (matching Python)
    var boot_block_offset = last_section.?.lma + last_section.?.size - image_addr;
    const padding_len = (4 - (boot_block_offset % 4)) & 3;
    boot_block_offset = boot_block_offset + padding_len;

    std.log.info("boot block offset = {x}", .{boot_block_offset});

    // Open output file and patch header
    var elf_file = try std.fs.cwd().openFile(output_file_name, .{ .mode = .read_write });
    defer elf_file.close();

    // Read and patch header (matching Python)
    try elf_file.seekTo(first_section.?.offset);
    
    var header_bytes: [44]u8 = undefined;
    _ = try elf_file.read(&header_bytes);
    
    var words: [11]u32 = undefined;
    for (0..11) |i| {
        words[i] = std.mem.readInt(u32, header_bytes[i * 4 ..][0..4], .little);
    }

    // Calculate vector checksum
    var vectsum: u32 = 0;
    for (words[0..7]) |word| {
        vectsum +%= word;
    }

    // Update fields (matching Python exactly)
    words[7] = (~vectsum & 0xFFFFFFFF) + 1;
    words[8] = IMAGE_HEADER_MARKER;
    words[9] = boot_block_offset;
    
    // Calculate CRC32 of first 10 words
    const crc_data = std.mem.sliceAsBytes(words[0..10]);
    words[10] = std.hash.Crc32.hash(crc_data) & 0xFFFFFFFF;

    std.log.info("Writing checksum {x:0>8} to file {s}", .{ vectsum, output_file_name });
    std.log.info("Writing CRC32 of header {x:0>8} to file {s}", .{ words[10], output_file_name });

    // Write patched header back
    try elf_file.seekTo(first_section.?.offset);
    for (words) |word| {
        try elf_file.writer().writeInt(u32, word, .little);
    }

    // Now dump last section, append boot block, and update section (matching Python)
    const temp_data_file = try std.fmt.allocPrint(allocator, "_{s}_data.bin", .{
        std.fs.path.basename(output_file_name)
    });
    defer allocator.free(temp_data_file);
    defer std.fs.cwd().deleteFile(temp_data_file) catch {};

    // Dump section
    const dump_section_arg = try std.fmt.allocPrint(allocator, "{s}={s}", .{ last_section.?.name, temp_data_file });
    defer allocator.free(dump_section_arg);
    
    const dump_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "arm-none-eabi-objcopy",
            "--dump-section",
            dump_section_arg,
            output_file_name,
        },
    });
    defer allocator.free(dump_result.stdout);
    defer allocator.free(dump_result.stderr);

    if (dump_result.term.Exited != 0) {
        std.log.err("Failed to dump section: {s}", .{dump_result.stderr});
        return 1;
    }

    // Append padding and boot block to temp file
    var temp_file = try std.fs.cwd().openFile(temp_data_file, .{ .mode = .read_write });
    defer temp_file.close();
    
    try temp_file.seekTo(try temp_file.getEndPos());
    
    // Write padding
    if (padding_len > 0) {
        const padding = [_]u8{0} ** 4;
        try temp_file.writeAll(padding[0..padding_len]);
    }

    // Write boot block (matching Python exactly)
    const img_total_len = boot_block_offset + 32; // boot_block_struct.size
    
    const boot_block = [8]u32{
        BOOT_BLOCK_MARKER,  // marker
        0,                  // image_id
        image_addr,         // image_addr
        img_total_len,      // image_len
        stated_size,        // stated_size
        0,                  // cert_offset
        0,                  // compat_offset
        0,                  // version
    };

    for (boot_block) |word| {
        try temp_file.writer().writeInt(u32, word, .little);
    }

    // Update section in ELF
    const update_section_arg = try std.fmt.allocPrint(allocator, "{s}={s}", .{ last_section.?.name, temp_data_file });
    defer allocator.free(update_section_arg);
    
    const update_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "arm-none-eabi-objcopy",
            "--update-section",
            update_section_arg,
            output_file_name,
            output_file_name,
        },
    });
    defer allocator.free(update_result.stdout);
    defer allocator.free(update_result.stderr);

    if (update_result.term.Exited != 0) {
        std.log.err("Failed to update section: {s}", .{update_result.stderr});
        return 1;
    }

    // Generate binary to check size (like Python does at the end)
    const bin_file = try std.fmt.allocPrint(allocator, "{s}.bin", .{output_file_name});
    defer allocator.free(bin_file);
    defer std.fs.cwd().deleteFile(bin_file) catch {};

    const bin_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "arm-none-eabi-objcopy",
            "-O",
            "binary",
            output_file_name,
            bin_file,
        },
    });
    defer allocator.free(bin_result.stdout);
    defer allocator.free(bin_result.stderr);

    if (bin_result.term.Exited == 0) {
        const bin_stat = try std.fs.cwd().statFile(bin_file);
        std.log.info("Binary size is {x:0>8} ({})", .{ bin_stat.size, bin_stat.size });
        
        if (bin_stat.size > stated_size) {
            std.log.err("Error: Binary file size ({x:0>8}) must be less or equal to stated size {x:0>8}", .{
                bin_stat.size, stated_size
            });
            return 1;
        }
        
        if (bin_stat.size != img_total_len) {
            std.log.err("File size {} different from expected {}", .{ bin_stat.size, img_total_len });
            return 1;
        }
    }

    return 0;
}

const Section = struct {
    name: []const u8,
    size: u32,
    lma: u32,
    offset: u32,
};