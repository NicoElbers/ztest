const ztest = @import("ztest");

const ExpectationState = ztest.ExpectationState;
const SomeException = ztest.SomeExpectation;

const expect = ztest.expect;

// Here we explore how to make an your own extension to ztest. These are the reccomended
// way to create your own (complex) assertions. There are stateful expectations, they
// are explained below but avoiding these is preferred.

// If we have a simple expectation we can simply do this
pub fn u32IsFour(state: *ExpectationState(u32)) !void {
    if (state.val == 4) return;

    return error.WasNotFour;
}

test "simple extension" {
    const input: u32 = 4;

    try expect(input).has(u32IsFour);
}

// If we want to expand this to take any integer we can do this
//
// `ExpectationState(T).ExpectationFunc` == `*const fn(*ExpectationState(T)) anyerror!void`
pub fn intIsFour(comptime T: type) ExpectationState(T).ExpectationFunc {
    const inner = struct {
        pub fn intIsFour(state: *ExpectationState(T)) !void {
            if (state.val == 4) return;

            return error.WasNotFour;
        }
    };

    return inner.intIsFour;
}

test "generic extension" {
    const input_u32: u32 = 4;
    const input_u64: u64 = 4;
    const input_comptime = 4;

    try expect(input_u32).has(intIsFour(u32));
    try expect(input_u64).has(intIsFour(u64));
    comptime try expect(input_comptime).has(intIsFour(comptime_int));
}
