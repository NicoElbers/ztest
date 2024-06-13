const ztest = @import("ztest");
const exp = ztest.exp;
const exp_fn = ztest.exp_fn;
const expect = exp.expect;
const expectAll = exp.expectAll;

const utils = @import("../tests.zig").utils;

test "expect all runtime types" {
    const info = @typeInfo(utils.AllRuntimeTypes);

    inline for (info.Struct.fields) |field| {
        const T: type = field.type;
        const val_ptr: *T = @ptrCast(@alignCast(@constCast(field.default_value.?)));
        const val: T = val_ptr.*;

        const state = expect(val);

        utils.nukeStack(1024);

        try expect(state.val).isEqualTo(val);
        try expect(state.err).isEqualTo(null);
        try expect(state.expected).isEqualTo(null);
        try expect(state.negative_expectation).isEqualTo(false);
    }
}

test "expect all comptime types" {
    const info = @typeInfo(utils.AllComptimeTypes);

    @setEvalBranchQuota(1_000_000);
    comptime {
        for (info.Struct.fields) |field| {
            const T: type = field.type;
            const val_ptr: *T = @ptrCast(@alignCast(@constCast(field.default_value.?)));
            const val: T = val_ptr.*;

            const state = expect(val);

            utils.nukeComptimeStack(1024);

            try state.has(StateIsUntouched(T).bind());
        }
    }
}

test "expectAll all runtime types" {
    const info = @typeInfo(utils.AllRuntimeTypes);

    inline for (info.Struct.fields) |field| {
        const T: type = field.type;
        const val_ptr: *T = @ptrCast(@alignCast(@constCast(field.default_value.?)));
        const val: T = val_ptr.*;

        try expectAll(val, &.{
            StateIsUntouched(T).bind(),
        });
    }
}

test "expectAll all comptime types" {
    const info = @typeInfo(utils.AllComptimeTypes);

    @setEvalBranchQuota(1_000_000);
    comptime {
        for (info.Struct.fields) |field| {
            const T: type = field.type;
            const val_ptr: *T = @ptrCast(@alignCast(@constCast(field.default_value.?)));
            const val: T = val_ptr.*;

            try expectAll(val, &.{
                StateIsUntouched(T).bind(),
            });
        }
    }
}

const SomeExpectation = ztest.SomeExpectation;
const ExpectationState = ztest.ExpectationState;

pub fn StateIsUntouched(comptime T: type) type {
    return struct {
        const Self = @This();

        pub inline fn bind() SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{});
        }

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            _ = self;

            try expect(state.negative_expectation).isEqualTo(false);
            try expect(state.expected).isEqualTo(null);
            try expect(state.err).isEqualTo(null);
            try expect(state.expected).isEqualTo(null);
            try expect(state.negative_expectation).isEqualTo(false);
        }
    };
}
