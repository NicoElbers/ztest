const std = @import("std");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Printer = @import("Printer.zig");
const Self = @This();

printer: Printer,
results: std.StringArrayHashMap(TestInformation),

pub const TestInformation = struct {
    args_fmt: ?[]const u8,
    status: Status,

    pub const Status = union(enum) { busy, passed, skipped, failed: anyerror };
};

pub fn init(alloc: Allocator, output_file: File) Self {
    const printer = Printer.init(output_file, alloc);

    return Self{
        .printer = printer,
        .results = std.StringArrayHashMap(TestInformation).init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.results.deinit();
}

pub fn initTest(self: *Self, name: []const u8, args_fmt: ?[]const u8) void {
    const info: TestInformation = .{
        .args_fmt = args_fmt,
        .status = .busy,
    };

    self.results.putNoClobber(name, info) catch
        @panic("Test initialization error");
}

pub fn updateTest(self: *Self, name: []const u8, status: TestInformation.Status) void {
    const info = self.results.getPtr(name) orelse {
        @panic("Cannot update test that hasn't been registered");
    };

    info.status = status;
}

/// Prints to the provided printer
pub fn printResults(self: Self) !void {
    var iter = self.results.iterator();

    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const info = entry.value_ptr;

        const status_tag = std.meta.activeTag(info.status);

        // Don't print anything for passing parameterized tests
        if (status_tag == .passed and info.args_fmt != null) continue;

        const printer = self.printer;

        try printer.writeAll(name);
        try printer.writeAll(": ");

        switch (info.status) {
            .passed => {
                try printer.setColor(.bright_green);
                try printer.writeAll("passed");
                try printer.setColor(.reset);
            },
            .skipped => {
                try printer.setColor(.bright_yellow);
                try printer.writeAll("skipped");
                try printer.setColor(.reset);
            },
            .busy => {
                try printer.setColor(.dim);
                try printer.writeAll("busy");
                try printer.setColor(.reset);
            },
            .failed => |err| {
                if (info.args_fmt) |args| {
                    try printer.setColor(.dim);
                    try printer.writeAll("(");
                    try printer.writeAll(args);
                    try printer.writeAll(") ");
                }

                try printer.setColor(.bright_red);
                try printer.writeAll("failed ");
                try printer.writeAll(@errorName(err));
                try printer.setColor(.reset);
            },
        }
        try printer.writeAll("\n");
    }
}
