printer: Printer,
alloc: Allocator,
tests: []TestInformation,
ptests: std.ArrayList(ParameterizedInformation),
printed_lines: u15,

pub const Status = union(enum) { printed, waiting, busy, passed, skipped, failed: anyerror };

pub const TestInformation = struct {
    status: Status,

    /// Represents the index into the ptest array where the parameterized test
    /// can be found
    ptests: std.ArrayList(usize),
    logs: std.ArrayList(u8),

    pub fn deinit(self: *TestInformation) void {
        self.ptests.deinit();
        self.logs.deinit();

        self.* = undefined;
    }
};

pub const ParameterizedInformation = struct {
    status: Status,
    parent_test_idx: usize,
    args_fmt: []const u8,
    logs: std.ArrayList(u8),

    pub fn deinit(self: *ParameterizedInformation, alloc: Allocator) void {
        alloc.free(self.args_fmt);
        self.logs.deinit();
        self.* = undefined;
    }
};

pub fn init(alloc: Allocator, test_amount: usize, output_file: File) !Self {
    const printer = Printer.init(output_file, alloc);

    // We can prealloc this because we get all the top level tests at comptime,
    // however for testability reasons, I still want to allocate at runtime
    const tests = try alloc.alloc(TestInformation, test_amount);
    @memset(tests, .{
        .status = .waiting,
        .ptests = .init(alloc),
        .logs = .init(alloc),
    });

    return Self{
        .printer = printer,
        .tests = tests,
        .ptests = .init(alloc),
        .alloc = alloc,
        .printed_lines = 0,
    };
}

pub fn deinit(self: *Self) void {
    for (self.ptests.items) |*ptest| {
        ptest.deinit(self.alloc);
    }
    self.ptests.deinit();

    for (self.tests) |*tst| {
        tst.deinit();
    }

    self.alloc.free(self.tests);
    self.* = undefined;
}

// TODO: Maybe try to return an index, and do something like the compiler does
// where you use a non exhaustive enum
pub fn initParameterizedTest(
    self: *Self,
    parent_test_idx: usize,
    args_fmt: []const u8,
) !void {
    assert(parent_test_idx < self.tests.len);
    assert(self.tests[parent_test_idx].status == .busy);

    try self.tests[parent_test_idx].ptests.append(self.ptests.items.len);

    try self.ptests.append(.{
        .status = .busy,
        .parent_test_idx = parent_test_idx,
        .args_fmt = try self.alloc.dupe(u8, args_fmt),
        .logs = .init(self.alloc),
    });
}

pub fn updateTestStatus(self: Self, test_idx: usize, status: Status) void {
    assert(test_idx < self.tests.len);

    self.tests[test_idx].status = status;
}

pub fn addTestLogs(self: Self, test_idx: usize, logs: []const u8) !void {
    assert(test_idx < self.tests.len);
    assert(self.tests[test_idx].status != .waiting);

    try self.tests[test_idx].logs.appendSlice(logs);
}

pub fn updateLastPtestStatus(self: Self, parent_test_idx: usize, status: Status) void {
    assert(parent_test_idx < self.tests.len);

    const parent = self.tests[parent_test_idx];

    assert(parent.ptests.items.len != 0);
    const idx = parent.ptests.items[parent.ptests.items.len - 1];

    self.ptests.items[idx].status = status;
}

pub fn addLastPtestLogs(self: Self, parent_test_idx: usize, logs: []const u8) !void {
    assert(parent_test_idx < self.tests.len);

    const parent = self.tests[parent_test_idx];

    assert(parent.ptests.items.len != 0);
    const idx = parent.ptests.items[parent.ptests.items.len - 1];

    try self.ptests.items[idx].logs.appendSlice(logs);
}

/// Prints to the provided printer
pub fn printResults(self: *Self, tests: []const std.builtin.TestFn) !void {
    const printer = &self.printer;
    const isTty = printer.file.isTty();

    if (isTty) {
        try self.clearPrinted();
    }

    for (self.tests, 0..) |*test_info, idx| {
        const status = &test_info.status;

        switch (status.*) {
            // Skip printed tests
            .printed => continue,

            // If we are not printing to a TTY, don't print intermediate
            // results
            .busy,
            .waiting,
            => if (!isTty) continue,

            else => {},
        }

        var lines_printed: u15 = 0;

        const test_name = tests[idx].name;
        try printer.writeAll(test_name);
        try printer.writeAll(": ");

        try printStatus(printer, test_info.status);
        try self.newLine(&lines_printed);

        if (test_info.logs.items.len != 0) {
            const logs = test_info.logs.items;

            try printer.writeAll(logs);

            const lines = std.mem.count(u8, logs, "\n");
            lines_printed +|= std.math.cast(u15, lines) orelse std.math.maxInt(u15);

            try self.newLine(&lines_printed);
        }

        ptest_loop: for (test_info.ptests.items) |ptest_info_idx| {
            const ptest_info = self.ptests.items[ptest_info_idx];

            if (status.* == .passed or
                status.* == .busy)
                continue :ptest_loop;

            try printer.writeAll("  ");
            try printer.setColor(.dim);
            try printer.writeAll(ptest_info.args_fmt);
            try printer.setColor(.reset);
            try printer.writeAll(" ");
            try printStatus(printer, ptest_info.status);

            try self.newLine(&lines_printed);
        }

        if (status.* == .waiting or status.* == .busy) {
            self.printed_lines +|= lines_printed;
        } else {
            status.* = .printed;
        }
    }
}

fn printStatus(printer: *Printer, status: Status) !void {
    switch (status) {
        .waiting,
        .busy,
        => {
            try printer.setColor(.dim);
            try printer.writeAll(@tagName(status));
        },
        .passed => {
            try printer.setColor(.bright_green);
            try printer.writeAll("passed");
        },
        .skipped => {
            try printer.setColor(.bright_yellow);
            try printer.writeAll("skipped");
        },
        .failed => |err| {
            try printer.setColor(.red);
            try printer.writeAll("failed (");
            try printer.writeAll(@errorName(err));
            try printer.writeAll(")");
        },
        .printed => unreachable,
    }
    try printer.setColor(.reset);
}

fn newLine(self: *Self, lines: *u15) !void {
    try self.printer.writeAll("\n");

    // If we would overflow, just saturate
    lines.* +|= 1;
}

pub fn clearPrinted(self: *Self) !void {
    if (self.printed_lines != 0)
        try self.printer.moveUpLine(self.printed_lines);
    try self.printer.clearBelow();
    self.printed_lines = 0;
}

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Printer = @import("Printer.zig");
const Self = @This();
