const std = @import("std");
const meta = std.meta;

const ztest = @import("../ztest.zig");
const runner = @import("ztest_runner");
const colors = @import("utils").colors;

const exp_fn = @import("functions.zig");
const exp_meta_fn = @import("meta_functions.zig");

const SomeExpectation = exp_fn.SomeExpectation;
const Allocator = std.mem.Allocator;

const expect = ztest.expect;

pub const ExpectationError = error{
    Failed,
    NotEqual,
    NotAValue,
    NotAnError,
    UnexpectedError,
    UnexpectedValue,
    OutOfBounds,
};

pub fn Expectation(comptime T: type) type {
    return struct {
        const Self = @This();

        val: T,
        expected: ?T = null,

        negative_expectation: bool = false,
        err: ?anyerror = null,

        alloc: Allocator = std.testing.allocator,

        fn negative(self: *Expectation(T)) []const u8 {
            if (self.negative_expectation) {
                return " not";
            } else {
                return "";
            }
        }

        pub fn handleError(self: *Expectation(T), err: anyerror) anyerror {
            self.err = err;
            try colors.setColor(std.io.getStdErr(), .dim);
            const err_msg = try std.fmt.allocPrint(
                self.alloc,
                " Expectation failed due to: {s}",
                .{@errorName(err)},
            );
            std.debug.print("{s}", .{err_msg});

            if (self.expected) |expected| {
                const instead_msg = try std.fmt.allocPrint(
                    self.alloc,
                    "; Expected{s} {any} but was {any}",
                    .{ self.negative(), expected, self.val },
                );
                std.debug.print("{s}", .{instead_msg});
            } else {
                const trace = @errorReturnTrace().?;
                try trace.format("", .{}, std.io.getStdOut().writer());
            }

            try colors.setColor(std.io.getStdErr(), .reset);

            return ExpectationError.Failed;
        }

        pub fn inRuntime(self: *Expectation(T)) *Expectation(T) {
            if (@inComptime()) {
                @compileError("Test should run in rumtime");
            }

            return self;
        }

        pub fn inComptime(self: *Expectation(T)) *Expectation(T) {
            if (!@inComptime()) {
                @panic("Test should be run in comptime");
            }

            return self;
        }

        pub fn has(self: *Expectation(T), arbitraryExpect: SomeExpectation(T)) !void {
            try arbitraryExpect.expect(self);
        }

        pub fn isEqualTo(self: *Expectation(T), expected: T) !void {
            exp_fn.isEqualTo(expected).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isNotEqualTo(self: *Expectation(T), expected: T) !void {
            exp_meta_fn.not(T, exp_fn.isEqualTo(expected)).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isError(self: *Expectation(T), expected: T) !void {
            exp_fn.isError(expected).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isNotError(self: *Expectation(T), expected: T) !void {
            exp_meta_fn.not(T, exp_fn.isError(expected)).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isValue(self: *Expectation(T)) !void {
            exp_fn.isValue(T).expect(self) catch |err| {
                return self.handleError(err);
            };
        }
    };
}

test "Expectation.inComptime" {
    comptime _ = expect(true).inComptime();
}

test "Expectation.inRuntime" {
    _ = expect(true).inRuntime();
}

test "Expectation.isEqualTo" {
    const val1: u60 = 123;
    const val2: u64 = 123;
    try expect(val1).isEqualTo(val2);
}

test "Expectation.isNotEqualTo" {
    const val1: u60 = 123;
    const val2: u64 = 124;
    try expect(val1).isNotEqualTo(val2);
}

test "Expectation.isError" {
    const ErrUnion = error{
        someErr,
        someOtherErr,
    };

    try expect(ErrUnion.someErr).isError(ErrUnion.someErr);
}

test "Expectation.isNotError" {
    const ErrUnion = error{
        someErr,
        someOtherErr,
    };

    try expect(ErrUnion.someErr).isNotError(ErrUnion.someOtherErr);
}
