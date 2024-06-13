const std = @import("std");
const meta = std.meta;
const colors = std.io.tty;

const ztest = @import("../ztest.zig");
const runner = @import("ztest_runner");

const exp_fn = @import("functions.zig");
const exp_meta_fn = @import("meta_functions.zig");

const SomeExpectation = exp_fn.SomeExpectation;
const Allocator = std.mem.Allocator;

pub const ExpectationError = error{
    Failed,
    NotEqual,
    NotAValue,
    NotAnError,
    UnexpectedError,
    UnexpectedValue,
    OutOfBounds,
};

pub fn ExpectationState(comptime T: type) type {
    return struct {
        const Self = @This();

        val: T,
        expected: ?T = null,

        negative_expectation: bool = false,
        err: ?anyerror = null,

        alloc: Allocator = std.testing.allocator,

        fn negative(self: *ExpectationState(T)) []const u8 {
            if (self.negative_expectation) {
                return " not";
            } else {
                return "";
            }
        }

        fn handleError(self: *ExpectationState(T), err: anyerror) anyerror {
            self.err = err;

            const config = colors.detectConfig(self.output);

            try config.setColor(std.io.getStdErr(), .dim);
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

            try config.setColor(std.io.getStdErr(), .reset);

            return ExpectationError.Failed;
        }

        pub fn inRuntime(self: *ExpectationState(T)) *ExpectationState(T) {
            if (@inComptime()) {
                @compileError("Test should run in rumtime");
            }

            return self;
        }

        pub fn inComptime(self: *ExpectationState(T)) *ExpectationState(T) {
            if (!@inComptime()) {
                @panic("Test should be run in comptime");
            }

            return self;
        }

        pub fn has(self: *ExpectationState(T), arbitraryExpect: SomeExpectation(T)) !void {
            try arbitraryExpect.expect(self);
        }

        pub fn isEqualTo(self: *ExpectationState(T), expected: T) !void {
            exp_fn.isEqualTo(expected).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isNotEqualTo(self: *ExpectationState(T), expected: T) !void {
            exp_meta_fn.not(T, exp_fn.isEqualTo(expected)).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isError(self: *ExpectationState(T), expected: T) !void {
            exp_fn.isError(expected).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isNotError(self: *ExpectationState(T), expected: T) !void {
            exp_meta_fn.not(T, exp_fn.isError(expected)).expect(self) catch |err| {
                return self.handleError(err);
            };
        }

        pub fn isValue(self: *ExpectationState(T)) !void {
            exp_fn.isValue(T).expect(self) catch |err| {
                return self.handleError(err);
            };
        }
    };
}

// NOTE: This is explicitly inlined to be able to return a pointer to the stack
pub inline fn expect(val: anytype) *ExpectationState(@TypeOf(val)) {
    var instance: ExpectationState(@TypeOf(val)) = ExpectationState(@TypeOf(val)){
        .val = val,
    };

    return &instance;
}

test expect {
    comptime try expect(123).isEqualTo(123);
    try expect(@as(u32, 123)).isEqualTo(123);
}

pub fn expectAll(val: anytype, expectations: []const SomeExpectation(@TypeOf(val))) !void {
    const expecta = expect(val);

    for (expectations) |expec| {
        expec.expect(expecta) catch |err| {
            return expecta.handleError(err);
        };
    }
}

test expectAll {
    try expectAll(@as(u32, 64), &.{
        exp_fn.isEqualTo(@as(u32, 64)),
        exp_fn.isValue(u32),
        exp_meta_fn.not(u32, exp_fn.isEqualTo(@as(u32, 123))),
    });
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
