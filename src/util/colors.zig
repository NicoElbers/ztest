const std = @import("std");
const io = std.io;
const builtin = @import("builtin");
const native_os = builtin.os.tag;

pub fn setColor(writer: anytype, color: Color) !void {
    if (native_os != .linux) @compileError("Fuck you non linux user (not supported rn)");

    const color_string = switch (color) {
        .black => "\x1b[30m",
        .red => "\x1b[31m",
        .green => "\x1b[32m",
        .yellow => "\x1b[33m",
        .blue => "\x1b[34m",
        .magenta => "\x1b[35m",
        .cyan => "\x1b[36m",
        .white => "\x1b[37m",
        .bright_black => "\x1b[90m",
        .bright_red => "\x1b[91m",
        .bright_green => "\x1b[92m",
        .bright_yellow => "\x1b[93m",
        .bright_blue => "\x1b[94m",
        .bright_magenta => "\x1b[95m",
        .bright_cyan => "\x1b[96m",
        .bright_white => "\x1b[97m",
        .bold => "\x1b[1m",
        .dim => "\x1b[2m",
        .reset => "\x1b[0m",
    };
    try writer.writeAll(color_string);
}

pub const Color = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    dim,
    bold,
    reset,
};
