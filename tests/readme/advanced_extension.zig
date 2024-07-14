// FIXME: See if there is any way I can remove the need for inline
// I really hate it

// TODO: Think if there are more advanced uses, maybe mocks or interface extensions
// although I don't know if those would be at all useful or feasable

const ztest = @import("ztest");

const ExpectationState = ztest.ExpectationState;
const SomeException = ztest.SomeExpectation;

const expect = ztest.expect;

// Here are stateful expectations. These take in some state which can create very
// powerful assertions, however if you can get away with the basic extensions
// that is preferred.

// If we want to use a complex stateful expectation, we need to do some more work
const U32IsNumber = struct {
    const Self = @This();

    number: u32,

    // Useful initialization function
    // This is inline because we're returning `&Self{}`. If we were to not
    // inline this function we would have to first create an instance and then
    // call bind or allocate to the heap, which is not ideal
    pub inline fn bind(number: u32) SomeException(u32) {
        return SomeException(u32).init(&Self{ .number = number });
    }

    // Here we also get a pointer to *const self, where our state lives
    pub fn expectation(self: *const Self, state: *ExpectationState(u32)) !void {
        if (state.val == self.number) return;

        return error.WasNotNumber;
    }
};

test "stateful extension" {
    const input1: u32 = 123;
    const expected1: u32 = 123;
    try expect(input1).hasRaw(U32IsNumber.bind(expected1));

    const input2: u32 = 456;
    const expected2: u32 = 456;
    try expect(input2).hasRaw(SomeException(u32).init(&U32IsNumber{ .number = expected2 }));
}

// Now finally if we really need everything we can make a generic stateful expectation
pub fn IntIsNumber(comptime T: type) type {
    return struct {
        const Self = @This();

        number: T,

        // Useful initialization function
        // This is inline because we're returning `&Self{}`. If we were to not
        // inline this function we would have to first create an instance and then
        // call bind or allocate to the heap, which is not ideal
        pub inline fn bind(number: T) SomeException(T) {
            return SomeException(T).init(&Self{ .number = number });
        }

        // Here we also get a pointer to *const self, where our state lives
        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            if (state.val == self.number) return;

            return error.WasNotNumber;
        }
    };
}

// A useful initialization function that binds everything at once
// Again explicitly inlined
pub inline fn intIsNumber(number: anytype) SomeException(@TypeOf(number)) {
    return IntIsNumber(@TypeOf(number)).bind(number);
}

// 3 different way to use the generic stateful extension we just made
test "generic stateful expectation" {
    const input_comptime = 890;
    const expect1 = 890;
    comptime try expect(input_comptime).hasRaw(intIsNumber(expect1));

    const input_u32: u32 = 123;
    const expect2: u32 = 123;
    try expect(input_u32).hasRaw(IntIsNumber(u32).bind(expect2));

    const input_u64: u64 = 456;
    const expect3: u64 = 456;
    try expect(input_u64).hasRaw(SomeException(u64).init(&IntIsNumber(u64){ .number = expect3 }));
}
