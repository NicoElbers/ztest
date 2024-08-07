const std = @import("std");
const meta = std.meta;
const colors = std.io.tty;

const ztest = @import("../ztest.zig");

const exp_fn = @import("functions.zig");
const exp_meta_fn = @import("meta_functions.zig");

const File = std.fs.File;

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
    ValueNotFound,
    NegativeExpectationFailed,
};

// TODO: Seriously consider whether I need expectation state, if I can go without
// it, it will make extensions easier and remove a lot of type hell
pub fn ExpectationState(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const ExpectationFunc: type = *const fn (*ExpectationState(T)) anyerror!void;

        // This is needed because null cannot be optional
        const ExpectedT = blk: {
            if (T == @TypeOf(null)) {
                break :blk T;
            } else {
                break :blk ?T;
            }
        };

        val: T,
        expected: ExpectedT = null,

        negative_expectation: bool = false,
        err: ?anyerror = null,

        alloc: Allocator = std.testing.allocator,

        output: File = std.io.getStdErr(),

        fn negative(self: *ExpectationState(T)) []const u8 {
            if (self.negative_expectation) {
                return " not";
            } else {
                return "";
            }
        }

        // FIXME: Completely rework this to give actually good error messages
        fn handleError(self: *ExpectationState(T), err: anyerror) anyerror {
            self.err = err;

            const config = colors.detectConfig(self.output);

            try config.setColor(std.io.getStdErr(), .dim);
            const err_msg = try std.fmt.allocPrint(
                self.alloc,
                " Expectation failed due to: {s}",
                .{@errorName(err)},
            );
            defer self.alloc.free(err_msg);
            std.debug.print("{s}", .{err_msg});

            if (self.expected) |expected| {
                const instead_msg = try std.fmt.allocPrint(
                    self.alloc,
                    "; Expected{s} {any} but was {any}",
                    .{ self.negative(), expected, self.val },
                );
                defer self.alloc.free(instead_msg);
                std.debug.print("{s}", .{instead_msg});
            } else {
                // HACK: I need to remove this at some point
                const trace = @errorReturnTrace().?;
                try trace.format("", .{}, std.io.getStdOut().writer());
            }

            try config.setColor(std.io.getStdErr(), .reset);

            return ExpectationError.Failed;
        }

        // TODO: Temporary workaround to get shit to work
        fn handleResult(self: *ExpectationState(T), res: anyerror!void) !void {
            if (!self.negative_expectation and std.meta.isError(res)) {
                return ExpectationError.NegativeExpectationFailed;
            }

            if (self.negative_expectation) {
                if (std.meta.isError(res)) {
                    return;
                } else {
                    try self.output.writeAll(" Negative Expecation failed");
                    return ExpectationError.NegativeExpectationFailed;
                }
            }

            _ = res catch |err| {
                return self.handleError(err);
            };
        }

        fn makeErrorMessage(self: *ExpectationState(T)) []const u8 {
            std.debug.assert(self.err != null);

            const err = self.err.?;
            _ = err;
        }

        pub fn inRuntime(self: *ExpectationState(T)) *ExpectationState(T) {
            if (@inComptime()) {
                @compileError("Test should run in runtime");
            }

            return self;
        }

        pub fn inComptime(self: *ExpectationState(T)) *ExpectationState(T) {
            if (!@inComptime()) {
                @panic("Test should be run in comptime");
            }

            return self;
        }

        pub fn not(self: *ExpectationState(T)) *ExpectationState(T) {
            self.negative_expectation = !self.negative_expectation;
            return self;
        }

        pub fn has(self: *ExpectationState(T), expectation: ExpectationFunc) !void {
            const res = expectation(self);
            return self.handleResult(res);
        }

        pub fn hasRaw(self: *ExpectationState(T), some_expectation: SomeExpectation(T)) !void {
            const res = some_expectation.expectation(self);
            return self.handleResult(res);
        }

        pub fn isEqualTo(self: *ExpectationState(T), expected: T) !void {
            const res = exp_fn.isEqualTo(expected).expectation(self);
            return self.handleResult(res);
        }

        pub fn isError(self: *ExpectationState(T), expected: T) !void {
            const res = exp_fn.isError(expected).expectation(self);
            return self.handleResult(res);
        }

        pub fn isAnyValue(self: *ExpectationState(T)) !void {
            const res = exp_fn.isValue(T).expectation(self);
            return self.handleResult(res);
        }
    };
}

// TODO: Research whether this inline can somehow be removed
// NOTE: This is explicitly inlined to be able to return a pointer to the stack
// this is needed to make ExpectationState mutable in chaining calls
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
    for (expectations) |some_expectation| {
        // const state = expect(val);
        // some_expectation.expectation(state) catch |err| {
        //     return state.handleError(err);
        // };
        try expect(val).hasRaw(some_expectation);
    }
}

// FIXME: Remove tests from here, they serve no purpose
// TEST: instead create more minimal tests that show off the specific function
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

test "Expectation.isError" {
    const ErrUnion = error{
        someErr,
        someOtherErr,
    };

    try expect(ErrUnion.someErr).isError(ErrUnion.someErr);
}

test {
    _ = @import("functions.zig");
    _ = @import("meta_functions.zig");
    _ = @import("checkers.zig");
}
