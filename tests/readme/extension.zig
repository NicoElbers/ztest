const ztest = @import("ztest");

const ExpectationState = ztest.ExpectationState;
const SomeException = ztest.SomeExpectation;

const expect = ztest.expect;

pub fn Extension(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        // Useful initialization function
        // This is inline because we're returning `&Self{}`. If we were to not
        // inline this function we would have to first create an instance and then
        // call bind or allocate to the heap, which is not ideal
        pub inline fn bind(val: T) SomeException(T) {
            return SomeException(T).init(&Self{ .value = val });
        }

        // We get a pointer to Expectation(T).
        pub fn expect(self: *const Self, expec: *ExpectationState(T)) !void {
            if (expec.val == self.value) return;

            return error.SomeError;
        }
    };
}

// Another useful function to create the extention and bind in one go:
// Again inlined because we return a pointer to the stack
pub inline fn extension(expected: anytype) SomeException(@TypeOf(expected)) {
    return Extension(@TypeOf(expected)).bind(expected);
}

// Using our extension
test "extension" {
    try expect(@as(u32, 123)).has(extension(@as(u32, 123)));
}
