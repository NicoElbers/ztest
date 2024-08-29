const std = @import("std");

// TODO: Create shallowEquals (maybe just std.meta.eql)
// TEST: In general test this more
pub fn deepEquals(a: anytype, b: @TypeOf(a)) bool {
    const a_info = @typeInfo(@TypeOf(a));
    const b_info = @typeInfo(@TypeOf(b));
    _ = b_info;

    return switch (a_info) {
        .void,
        .noreturn,
        .null,
        .undefined,
        => true, // Only one value

        // TODO: Verify
        .@"enum",
        => true, // Doesn't compile otherwise

        .int,
        .comptime_int,
        .bool,
        => a == b, // Simple equality

        // TEST: Different error sets
        .error_set,
        // TEST: Capitalization
        .enum_literal,
        // TEST: types with different subtypes
        .type,
        => a == b, // Simple comptime equality

        .@"fn",
        // TODO: Maybe compile error, only allow shallow eql
        // Maybe add a special eql that allows this
        .@"opaque",
        .frame,
        .@"anyframe",
        => a == b, // pointer equality

        // TEST: Look at std tests
        .float,
        .comptime_float,
        => floatEql(a, b),

        // TEST: I need edge cases for both of these
        .array,
        .vector,
        => deepEquals(&a, &b), //Make use of pointerEql

        .@"struct" => structEql(a, b),
        .optional => optionalEql(a, b),
        .error_union => errorUnionEql(a, b),
        .@"union" => |info| unionEql(a, b, info),
        .pointer => |ptr| pointerEql(a, b, ptr),
    };
}

// std.meta.eql

pub fn unionEql(a: anytype, b: @TypeOf(a), info: std.builtin.Type.Union) bool {
    const T = @TypeOf(a);
    const a_info = @typeInfo(T);
    if (a_info != .@"union")
        @compileError("unionEql only works for unions");

    if (info.tag_type) |UnionTag| {
        const tag_a = std.meta.activeTag(a);
        const tag_b = std.meta.activeTag(b);
        if (tag_a != tag_b) return false;

        inline for (info.fields) |field_info| {
            if (@field(UnionTag, field_info.name) == tag_a) {
                return deepEquals(
                    @field(a, field_info.name),
                    @field(b, field_info.name),
                );
            }
        }
        return false;
    }

    @compileError("cannot compare untagged union type " ++ @typeName(T));
}

pub fn errorUnionEql(a: anytype, b: @TypeOf(a)) bool {
    const info = @typeInfo(@TypeOf(a));
    if (info != .error_union)
        @compileError("optionalEql only works for optionals");

    const a_inner = a catch |a_err| {
        _ = b catch |b_err| {
            return deepEquals(a_err, b_err);
        };
        return false;
    };

    const b_inner = b catch {
        return false; // we already know a is not an error
    };

    return deepEquals(a_inner, b_inner);
}

pub fn optionalEql(maybe_a: anytype, maybe_b: @TypeOf(maybe_a)) bool {
    const info = @typeInfo(@TypeOf(maybe_a));
    if (info != .optional)
        @compileError("optionalEql only works for optionals");

    if (maybe_a) |a| {
        if (maybe_b) |b| {
            return deepEquals(a, b);
        } else {
            return false;
        }
    } else {
        if (maybe_b == null) {
            return true;
        } else {
            return false;
        }
    }
}

pub fn structEql(a: anytype, b: @TypeOf(a)) bool {
    const info = @typeInfo(@TypeOf(a));
    if (info != .@"struct") @compileError("structEql is only supported for structs");

    inline for (info.@"struct".fields) |field_info| {
        if (!deepEquals(
            @field(a, field_info.name),
            @field(b, field_info.name),
        )) return false;
    }
    return true;
}

pub fn pointerEql(a: anytype, b: @TypeOf(a), ptr: std.builtin.Type.Pointer) bool {
    const T = @TypeOf(a);
    const info = @typeInfo(T);
    if (info != .pointer) @compileError("pointerEql is only supported for pointer");
    if (a == b) return true; // fast path if the addresses are the same

    const Child = info.pointer.child;

    // TODO: Maybe compile error, only allow shallow eql
    // Maybe add a special eql that allows this
    if (Child == anyopaque)
        return a == b;

    const sentinel: ?Child = blk: {
        if (info.pointer.sentinel) |s| {
            break :blk @as(Child, @ptrCast(@alignCast(s)));
        } else {
            break :blk null;
        }
    };

    switch (ptr.size) {
        .C => @compileError(@typeName(T) ++ " is a c ptr"),
        .One,
        => {
            if (@typeInfo(Child) == .@"fn")
                return a == b;

            return deepEquals(a.*, b.*);
        },
        .Many => {
            if (sentinel) |s| {
                const limit = std.math.maxInt(u29);
                for (0..limit) |idx| {
                    const a_item = a[idx];
                    const b_item = b[idx];
                    if (a_item == s and b_item == s)
                        return true;

                    if (!deepEquals(a_item, b_item))
                        return false;
                }
                return true;
            }
            @compileError("pointerEql is not yet supoorted for many pointers without a sentinel");
        },
        .Slice => {
            if (a.len != b.len) return false;
            for (a, b) |a_item, b_item| {
                if (sentinel) |s| {
                    if (a_item == s and b_item == s)
                        return true;
                }

                if (!deepEquals(a_item, b_item))
                    return false;
            }
            return true;
        },
    }
}

pub fn floatEql(a: anytype, b: @TypeOf(a)) bool {
    const math = @import("std").math;

    const T = @TypeOf(a);
    const info = @typeInfo(T);
    const tolerance = switch (info) {
        .float => math.sqrt(math.floatEps(T)),
        .comptime_float => 1e-4,
        else => @compileError("floatEql is only supported for floats"),
    };

    return math.approxEqRel(T, a, b, tolerance);
}
