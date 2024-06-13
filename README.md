# Ztest

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

## Extensibility

One of the core features of the library is to be able to easily extend exceptions.

You must implement the SomeException(type) interface:
`pub fn expect(self: *const @This(), expec: *Expectation(T)) !void {}`

```zig
const ztest = @import("ztest");

const Expectation = ztest.Expectation;
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
        pub fn expect(self: *const Self, expec: *Expectation(T)) !void {
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
```
