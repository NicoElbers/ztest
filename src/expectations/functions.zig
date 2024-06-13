// fn Template(comptime T: type) type {
//     return struct {
//         const Self = @This();
//
//         pub inline fn bind() SomeExpectation(T) {
//             return SomeExpectation(T).init(&Self{});
//         }
//
//         pub fn expect(self: *const Self, expec: *Expectation(T)) !void {
//
//         }
//
//         pub fn make(self: *const Self) SomeExpectation(T) {
//             return SomeExpectation(T).init(self);
//         }
//     };
// }

//switch (@typeInfo(T)) {
//     .Type,
//     .Void,
//     .Bool,
//     .NoReturn,
//     .Int,
//     .Float,
//     .Pointer,
//     .Array,
//     .Struct,
//     .ComptimeFloat,
//     .ComptimeInt,
//     .Undefined,
//     .Null,
//     .Optional,
//     .ErrorUnion,
//     .ErrorSet,
//     .Enum,
//     .Union,
//     .Fn,
//     .Opaque,
//     .Frame,
//     .AnyFrame,
//     .Vector,
//     .EnumLiteral,
//      => {},
// }

const std = @import("std");

const ztest = @import("../ztest.zig");
const exp = @import("core.zig");

const expect = ztest.expect;
const Expectation = exp.ExpectationState;
const ExpectationError = exp.ExpectationError;

pub fn SomeExpectation(comptime T: type) type {
    return struct {
        const SelfPtr = *const anyopaque;

        ptr: SelfPtr,
        expectFn: *const fn (SelfPtr, *Expectation(T)) anyerror!void,

        pub inline fn init(ptr: anytype) SomeExpectation(T) {
            const P = @TypeOf(ptr);
            const ptr_info = @typeInfo(P);

            if (ptr_info != .Pointer) @compileError("Pointer must be of type pointer");
            if (ptr_info.Pointer.size != .One)
                @compileError("Pointer must be a single item pointer");

            const Child = ptr_info.Pointer.child;

            if (!std.meta.hasFn(Child, "expect")) @compileError("Type " ++ @typeName(Child) ++ " does not have an expect function");

            const wrapper = struct {
                pub fn inner(pointer: SelfPtr, expectation: *Expectation(T)) anyerror!void {
                    const self: P = @ptrCast(@alignCast(pointer));
                    return Child.expect(self, expectation);
                }
            };

            return SomeExpectation(T){
                .ptr = ptr,
                .expectFn = wrapper.inner,
            };
        }

        pub fn expect(self: SomeExpectation(T), expectation: *Expectation(T)) !void {
            return self.expectFn(self.ptr, expectation);
        }
    };
}

pub inline fn isError(expected: anytype) SomeExpectation(@TypeOf(expected)) {
    return IsError(@TypeOf(expected)).bind(expected);
}
pub fn IsError(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Type,
        .Void,
        .Bool,
        .NoReturn,
        .Int,
        .Float,
        .Pointer,
        .Array,
        .Struct,
        .ComptimeFloat,
        .ComptimeInt,
        .Undefined,
        .Null,
        .Optional,
        .Enum,
        .Union,
        .Fn,
        .Opaque,
        .Frame,
        .AnyFrame,
        .Vector,
        .EnumLiteral,
        => @compileError("Type " ++ @typeName(T) ++ " cannot be an error"),

        .ErrorUnion,
        .ErrorSet,
        => {},
    }

    return struct {
        const Self = @This();

        err: T,

        pub inline fn bind(err: T) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .err = err,
            });
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }

        pub fn expect(self: *const Self, expec: *Expectation(T)) !void {
            expec.expected = self.err;

            switch (@typeInfo(T)) {
                .ErrorUnion => {
                    _ = expec.val catch |err| {
                        if (err == self.err) return;
                    };
                },
                .ErrorSet => {
                    if (expec.val == self.err) return;
                },

                else => unreachable,
            }

            return ExpectationError.UnexpectedValue;
        }
    };
}

pub inline fn isValue(comptime T: type) SomeExpectation(T) {
    return IsValue(T).bind();
}
pub fn IsValue(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Type,
        .Void,
        .Bool,
        .NoReturn,
        .Int,
        .Float,
        .Pointer,
        .Array,
        .Struct,
        .ComptimeFloat,
        .ComptimeInt,
        .Undefined,
        .Null,
        .Optional,
        .ErrorUnion,
        .ErrorSet,
        .Enum,
        .Union,
        .Fn,
        .Opaque,
        .Frame,
        .AnyFrame,
        .Vector,
        .EnumLiteral,
        => {},
    }

    return struct {
        const Self = @This();

        pub inline fn bind() SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{});
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }

        pub fn expect(self: *const Self, expec: *Expectation(T)) !void {
            _ = self;
            switch (@typeInfo(T)) {
                .ErrorSet => {},
                .ErrorUnion => {
                    if (!std.meta.isError(expec.val)) return;
                },
                .Optional => {
                    if (expec.val) |_| {
                        return;
                    }
                },

                else => return,
            }

            return ExpectationError.NotAValue;
        }
    };
}

pub inline fn isEqualTo(expected: anytype) SomeExpectation(@TypeOf(expected)) {
    return IsEqualTo(@TypeOf(expected)).bind(expected);
}
pub fn IsEqualTo(comptime T: type) type {
    // TODO: Double check that I actually permit everything
    switch (@typeInfo(T)) {
        .Type,
        .Void,
        .Bool,
        .NoReturn,
        .Int,
        .Float,
        .Pointer,
        .Array,
        .Struct,
        .ComptimeFloat,
        .ComptimeInt,
        .Undefined,
        .Null,
        .Optional,
        .ErrorUnion,
        .ErrorSet,
        .Enum,
        .Union,
        .Fn,
        .Opaque,
        .Frame,
        .AnyFrame,
        .Vector,
        .EnumLiteral,
        => {},
    }

    return struct {
        const Self = @This();

        val: T,

        pub inline fn bind(val: T) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .val = val,
            });
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }

        pub fn expect(self: *const Self, expec: *Expectation(T)) !void {
            expec.expected = self.val;

            // TODO: See if I can make std.meta.eql better/ more explicit
            if (std.meta.eql(self.val, expec.val)) return;

            return ExpectationError.NotEqual;
        }
    };
}

test IsEqualTo {
    const val: u32 = 123;

    try expect(@as(u32, 123))
        .inRuntime()
        .has(IsEqualTo(u32).bind(val));
}

pub const IsBetweenConfig = struct {
    include_lower: bool = true,
    include_upper: bool = false,
};
pub fn IsBetween(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Float,
        .ComptimeFloat,
        => @compileError("Use IsBetweenF for floats instead"),
        // TODO: Make IsBetweenF

        .Type,
        .Void,
        .Bool,
        .NoReturn,
        .Pointer,
        .Array,
        .Struct,
        .Undefined,
        .Null,
        .ErrorSet,
        .Enum,
        .Union,
        .Fn,
        .Opaque,
        .Frame,
        .AnyFrame,
        .Vector,
        .EnumLiteral,
        => @compileError("Type " ++ @typeName(T) ++ " is not supported"),

        .Int,
        .ComptimeInt,
        => {},

        .Optional,
        .ErrorUnion,
        => @compileError("TODO: make " ++ @typeName(@TypeOf(@This())) ++ " work"),
    }

    return struct {
        const Self = @This();

        lower: T,
        upper: T,
        config: IsBetweenConfig,

        pub inline fn bind(lower: T, upper: T, config: IsBetweenConfig) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .lower = lower,
                .upper = upper,
                .config = config,
            });
        }

        pub fn expect(self: *const Self, expec: *Expectation(T)) !void {
            const val: T = expec.val;

            // TODO: set expec.expected here. AKA redo the system :')

            if (self.config.include_lower) {
                if (val < self.lower) return ExpectationError.OutOfBounds;
            } else {
                if (val <= self.lower) return ExpectationError.OutOfBounds;
            }

            if (self.config.include_upper) {
                if (val > self.upper) return ExpectationError.OutOfBounds;
            } else {
                if (val >= self.upper) return ExpectationError.OutOfBounds;
            }
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }
    };
}
