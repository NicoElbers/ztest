# Ztest
##TODO: update the readme, pretty sure this still compiles, but the projects moved further with parameterized tests.

Ztest is a testing library for the Zig programming lanuage. It's currenly in very early development.

The basic syntax for the library is as follows:

```zig
const ztest = @import("ztest");
const exp_fn = ztest.exp_fn;
const exp_meta_fn = ztest.exp_meta_fn;

const expect = ztest.expect;
const expectAll = ztest.expectAll;

test "basic expectation" {
    try expect(@as(u32, 123)).isEqualTo(123);
}

test "multiple expectations" {
    try expectAll(@as(u32, 123), &.{
        exp_fn.isEqualTo(@as(u32, 123)),
        exp_fn.isValue(u32),
        exp_meta_fn.not(u32, exp_fn.isEqualTo(@as(u32, 456))),
    });
}
```

## Features

### Extensibility

One of the core features of the library is to be able to easily extend exceptions. There are 4 ways to do this:

```zig
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
```

#### Advanced extensions

//TODO: write text

```zig
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
```
