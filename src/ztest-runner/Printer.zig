const std = @import("std");
const windows = std.os.windows;
const tty = std.io.tty;

const Allocator = std.mem.Allocator;
const ColorConfig = tty.Config;
const Color = tty.Color;
const File = std.fs.File;
const Writer = File.Writer;

const WriterError = std.posix.WriteError;
const ColorError = WriterError || windows.SetConsoleTextAttributeError;

const Self = @This();

clr_config: ColorConfig,
writer: Writer,
ansi_support: bool,
alloc: Allocator,

pub fn init(output_file: File, alloc: Allocator) Self {
    const clr_config = tty.detectConfig(output_file);
    const writer = output_file.writer();
    const ansi_support = output_file.getOrEnableAnsiEscapeSupport();

    return Self{
        .clr_config = clr_config,
        .writer = writer,
        .ansi_support = ansi_support,
        .alloc = alloc,
    };
}

pub fn printFmt(self: Self, comptime fmt: []const u8, args: anytype) !void {
    const txt = try std.fmt.allocPrint(self.alloc, fmt, args);
    defer self.alloc.free(txt);
    return self.writeAll(txt);
}

pub fn writeAll(self: Self, bytes: []const u8) WriterError!void {
    return self.writer.writeAll(bytes);
}

pub fn setColor(self: Self, color: Color) ColorError!void {
    return self.clr_config.setColor(self.writer, color);
}

pub fn clearLine(self: Self) WriterError!void {
    std.debug.assert(self.ansi_support);

    try self.writeAll("\x1b[G");
    try self.writeAll("\x1b[K");
}

// u15 because "<n> cannot be larger than 32,767 (maximum short value)"
// https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
pub fn moveUpLine(self: Self, count: u15) (WriterError || std.fmt.AllocPrintError)!void {
    std.debug.assert(self.ansi_support);

    const move_str = try std.fmt.allocPrint(
        self.alloc,
        "\x1b[{d}F",
        .{count},
    );
    defer self.alloc.free(move_str);

    try self.writeAll(move_str);
}

// u15 because "<n> cannot be larger than 32,767 (maximum short value)"
// https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
pub fn moveDownLine(self: Self, count: u15) (WriterError || std.fmt.AllocPrintError)!void {
    std.debug.assert(self.ansi_support);

    const move_str = try std.fmt.allocPrint(
        self.alloc,
        "\x1b[{d}E",
        .{count},
    );
    defer self.alloc.free(move_str);

    try self.writeAll(move_str);
}

pub fn moveToStartOfLine(self: Self) WriterError!void {
    try self.writeAll("\x1b[G");
}

pub fn saveCursorPosition(self: Self) WriterError!void {
    std.debug.assert(self.ansi_support);

    try self.writeAll("\x1b[s");
}

pub fn loadCursorPosition(self: Self) WriterError!void {
    std.debug.assert(self.ansi_support);

    try self.writeAll("\x1b[u");
}
