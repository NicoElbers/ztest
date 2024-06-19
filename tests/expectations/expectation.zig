const ztest = @import("ztest");
const exp = ztest.exp;
const exp_fn = ztest.exp_fn;
const expect = exp.expect;
const expectAll = exp.expectAll;
const parameterizedTest = ztest.parameterizedTest;

const utils = @import("../tests.zig").utils;

test "expect all runtime types" {
    const Errors = error{ someErr, someOtherErr };
    const SomeEnum = enum { a, b };
    const SomeTaggedUnion = union(enum) { a: u32, b: u64 };

    const inner = struct {
        pub fn unchanged(in: anytype) !void {
            const state = expect(in);
            const T = @TypeOf(state);

            utils.nukeStack(1024);

            try expect(state).has(stateUnchanged(T));
        }
    };

    try parameterizedTest(inner.unchanged, .{
        .{true},
        .{@as(u8, 123)},
        .{@as(f32, 32.34)},
        .{@as(*const u8, &43)},
        .{[_]u8{ 1, 2, 3 }},
        .{@as(?u8, null)},
        .{@as(Errors!u8, Errors.someErr)},
        .{@as(Errors!u8, 8)},
        .{@as(Errors, Errors.someErr)},
        .{SomeEnum.a},
        .{SomeTaggedUnion{ .a = 543 }},
        .{@as(*const anyopaque, &8)},
        .{@as(@Vector(5, u8), @splat(13))},
    });
}

test "expect all comptime types" {
    const Errors = error{ someErr, someOtherErr };
    const SomeEnum = enum { a, b };
    const SomeTaggedUnion = union(enum) { a: u32, b: u64 };

    const inner = struct {
        pub fn unchanged(in: anytype) !void {
            const state = expect(in);
            const T = @TypeOf(state);

            utils.nukeComptimeStack(1024);

            try expect(state).has(stateUnchanged(T));
        }
    };

    @setEvalBranchQuota(1_000_000);
    comptime try parameterizedTest(inner.unchanged, .{
        .{@as(type, u8)},
        .{void},
        .{inner},
        .{123.543},
        .{123},
        .{inner.unchanged},
        .{.A},

        // The runtime types as well
        .{true},
        .{@as(u8, 123)},
        .{@as(f32, 32.34)},
        .{@as(*const u8, &43)},
        .{[_]u8{ 1, 2, 3 }},
        .{@as(?u8, null)},
        .{@as(Errors!u8, Errors.someErr)},
        .{@as(Errors!u8, 8)},
        .{@as(Errors, Errors.someErr)},
        .{SomeEnum.a},
        .{SomeTaggedUnion{ .a = 543 }},
        .{@as(*const anyopaque, &8)},
        .{@as(@Vector(5, u8), @splat(13))},
    });
}

// test "expectAll all runtime types" {
//     const info = @typeInfo(utils.AllRuntimeTypes);

//     inline for (info.Struct.fields) |field| {
//         const T: type = field.type;
//         const val_ptr: *T = @ptrCast(@alignCast(@constCast(field.default_value.?)));
//         const val: T = val_ptr.*;

//         try expectAll(val, &.{
//             StateIsUntouched(T).bind(),
//         });
//     }
// }

// test "expectAll all comptime types" {
//     const info = @typeInfo(utils.AllComptimeTypes);

//     @setEvalBranchQuota(1_000_000);
//     comptime {
//         for (info.Struct.fields) |field| {
//             const T: type = field.type;
//             const val_ptr: *T = @ptrCast(@alignCast(@constCast(field.default_value.?)));
//             const val: T = val_ptr.*;

//             try expectAll(val, &.{
//                 StateIsUntouched(T).bind(),
//             });
//         }
//     }
// }

const SomeExpectation = ztest.SomeExpectation;
const ExpectationState = ztest.ExpectationState;

pub fn stateUnchanged(comptime T: type) ExpectationState(T).ExpectationFunc {
    const inner = struct {
        pub fn stateIsUntouched(state: *ExpectationState(T)) !void {
            try expect(state.negative_expectation).isEqualTo(false);
            try expect(state.expected).isEqualTo(null);
            try expect(state.err).isEqualTo(null);
            try expect(state.expected).isEqualTo(null);
            try expect(state.negative_expectation).isEqualTo(false);
        }
    };

    return inner.stateIsUntouched;
}
