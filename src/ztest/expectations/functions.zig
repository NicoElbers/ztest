// TEST: Create at least 1 simple test to show off the expectation

const std = @import("std");

const ztest = @import("../ztest.zig");
const checker = @import("checkers.zig");
const exp = @import("core.zig");

const expect = ztest.expect;
const ExpectationState = exp.ExpectationState;
const ExpectationError = exp.ExpectationError;

pub fn SomeExpectation(comptime T: type) type {
    return struct {
        const SelfPtr = *const anyopaque;

        ptr: SelfPtr,
        expectFn: *const fn (SelfPtr, *ExpectationState(T)) anyerror!void,

        pub fn init(ptr: anytype) SomeExpectation(T) {
            const P = @TypeOf(ptr);
            const ptr_info = @typeInfo(P);

            if (ptr_info != .Pointer) @compileError("Pointer must be of type pointer");
            if (ptr_info.Pointer.size != .One)
                @compileError("Pointer must be a single item pointer");

            const Child = ptr_info.Pointer.child;

            if (!std.meta.hasFn(Child, "expectation"))
                @compileError("Type " ++ @typeName(Child) ++ " does not have an expect function");

            const ArgsT: type = @TypeOf(@field(Child, "expectation"));
            const args = std.meta.ArgsTuple(ArgsT);
            const args_tuple = @typeInfo(args).Struct;
            if (args_tuple.fields.len != 2)
                @compileError("'expect' function in type " ++ @typeName(Child) ++ " should have 2 parameters");
            if (args_tuple.fields[0].type != *const Child)
                @compileError("'expect' function should have '*const " ++ @typeName(Child) ++ "' as it's first parameter");
            if (args_tuple.fields[1].type != *ExpectationState(T))
                @compileError("'expect' function should have '*" ++ @typeName(ExpectationState(T)) ++ "' as it's second parameter");

            const wrapper = struct {
                pub fn inner(pointer: SelfPtr, state: *ExpectationState(T)) anyerror!void {
                    const self: P = @ptrCast(@alignCast(pointer));
                    return Child.expectation(self, state);
                }
            };

            return SomeExpectation(T){
                .ptr = ptr,
                .expectFn = wrapper.inner,
            };
        }

        pub fn expectation(self: SomeExpectation(T), state: *ExpectationState(T)) !void {
            return self.expectFn(self.ptr, state);
        }
    };
}

pub inline fn isError(expected: anytype) SomeExpectation(@TypeOf(expected)) {
    return IsError(@TypeOf(expected)).bind(expected);
}
pub fn IsError(comptime T: type) type {
    switch (@typeInfo(T)) {
        .ErrorUnion,
        .ErrorSet,
        => {},

        else => @compileError("Type " ++ @typeName(T) ++ " cannot be an error"),
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

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            state.expected = self.err;

            switch (@typeInfo(T)) {
                .ErrorUnion => {
                    _ = state.val catch |err| {
                        if (err == self.err) return;
                    };
                },
                .ErrorSet => {
                    if (state.val == self.err) return;
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
        else => {},
    }

    return struct {
        const Self = @This();

        pub inline fn bind() SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{});
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            _ = self;
            switch (@typeInfo(T)) {
                .ErrorSet => {},
                .ErrorUnion => {
                    if (!std.meta.isError(state.val)) return;
                },
                .Optional => {
                    if (state.val) |_| {
                        return;
                    }
                },

                else => return,
            }

            return ExpectationError.NotAValue;
        }
    };
}

// TODO: Make isShallowEqualTo
pub inline fn isEqualTo(expected: anytype) SomeExpectation(@TypeOf(expected)) {
    return IsEqualTo(@TypeOf(expected)).bind(expected);
}
pub fn IsEqualTo(comptime T: type) type {
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

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            state.expected = self.val;

            if (!checker.deepEquals(self.val, state.val))
                return ExpectationError.NotEqual;
        }
    };
}

test IsEqualTo {
    const val: u32 = 123;

    try expect(@as(u32, 123))
        .inRuntime()
        .hasRaw(IsEqualTo(u32).bind(val));
}

pub const RangeConfig = struct {
    include_lower: bool = true,
    include_upper: bool = false,
};

pub fn IsBetween(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Int,
        .ComptimeInt,
        => {},

        .Float,
        .ComptimeFloat,
        => @compileError("Use IsBetweenF for floats instead"),
        // TODO: Make IsBetweenF
        // why? Just extend the config a little maybe not even

        else => @compileError("Type " ++ @typeName(T) ++ " is not supported"),
    }

    return struct {
        const Self = @This();

        lower: T,
        upper: T,
        config: RangeConfig,

        pub inline fn bind(lower: T, upper: T, config: RangeConfig) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .lower = lower,
                .upper = upper,
                .config = config,
            });
        }

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            const val: T = state.val;

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

pub fn isLessThan(upper: anytype, config: RangeConfig) SomeExpectation(@TypeOf(upper)) {
    return IsLessThan(@TypeOf(upper)).bind(upper, config);
}
pub fn IsLessThan(comptime T: type) type {
    return struct {
        const Self = @This();

        upper: T,
        config: RangeConfig,

        pub inline fn bind(upper: T, config: RangeConfig) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .upper = upper,
                .config = config,
            });
        }

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            const val = state.val;

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

pub fn isMoreThan(upper: anytype, config: RangeConfig) SomeExpectation(@TypeOf(upper)) {
    return IsMoreThan(@TypeOf(upper)).bind(upper, config);
}
pub fn IsMoreThan(comptime T: type) type {
    return struct {
        const Self = @This();

        lower: T,
        config: RangeConfig,

        pub inline fn bind(lower: T, config: RangeConfig) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .lower = lower,
                .config = config,
            });
        }

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            const val = state.val;

            if (self.config.include_lower) {
                if (val < self.lower) return ExpectationError.OutOfBounds;
            } else {
                if (val <= self.lower) return ExpectationError.OutOfBounds;
            }
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }
    };
}

pub fn Contains(comptime T: type) type {
    const Child: type = switch (@typeInfo(T)) {
        .Array => |arr| return arr.child,
        .Vector => |vec| return vec.child,
        .Pointer => |ptr| return ptr.child,

        else => @compileError(@typeName(T) ++ " does not contain anything"),
    };

    return struct {
        const Self = @This();

        item: Child,

        pub inline fn bind(expected: Child) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .item = expected,
            });
        }

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            for (state.val) |item| {
                if (std.meta.eql(item, self.item)) return;
            }

            return ExpectationError.ValueNotFound;
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }
    };
}

pub const ContainConfig = struct {
    in_any_order: bool = false,
    length: ?usize = null,
};

pub fn ContainsAll(comptime T: type) type {
    const Child: type = switch (@typeInfo(T)) {
        .Array => |arr| return arr.child,
        .Vector => |vec| return vec.child,
        .Pointer => |ptr| return ptr.child,

        else => @compileError(@typeName(T) ++ " does not contain anything"),
    };

    return struct {
        const Self = @This();

        item: Child,

        pub inline fn bind(expected: Child) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .item = expected,
            });
        }

        pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {
            for (state.val) |item| {
                if (std.meta.eql(item, self.item)) return;
                @compileError("AAAAAAA");
            }

            return ExpectationError.ValueNotFound;
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }
    };
}
