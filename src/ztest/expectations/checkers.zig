const std = @import("std");

pub fn deepEquals(a: anytype, b: @TypeOf(a)) bool {
    const a_info = @typeInfo(@TypeOf(a));
    const b_info = @typeInfo(@TypeOf(b));
    _ = b_info;

    return switch (a_info) {
        .Void,
        .NoReturn,
        .Null,
        .Undefined,
        => true, // Only one value

        .Enum,
        => true, // Doesn't compile otherwise

        .Int,
        .ComptimeInt,
        .Bool,
        => a == b, // Simple equality

        .ErrorSet,
        .EnumLiteral,
        .Type,
        => a == b, // Simple comptime equality

        .Fn,
        .Opaque,
        .Frame,
        .AnyFrame,
        => a == b, // pointer equality

        .Float,
        .ComptimeFloat,
        => floatEql(a, b),

        .Array,
        .Vector,
        => deepEquals(&a, &b), //Make use of pointerEql

        .Struct => structEql(a, b),
        .Optional => optionalEql(a, b),
        .ErrorUnion => errorUnionEql(a, b),
        .Union => |info| unionEql(a, b, info),
        .Pointer => |ptr| pointerEql(a, b, ptr),
    };
}

// std.meta.eql

pub fn unionEql(a: anytype, b: @TypeOf(a), info: std.builtin.Type.Union) bool {
    const T = @TypeOf(a);
    const a_info = @typeInfo(T);
    if (a_info != .Union)
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
    if (info != .ErrorUnion)
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
    if (info != .Optional)
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
    if (info != .Struct) @compileError("structEql is only supported for structs");

    inline for (info.Struct.fields) |field_info| {
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
    if (info != .Pointer) @compileError("pointerEql is only supported for pointer");
    if (a == b) return true; // fast path if the addresses are the same

    const Child = info.Pointer.child;

    if (Child == anyopaque)
        return a == b; // TODO: fix

    const sentinel: ?Child = blk: {
        if (info.Pointer.sentinel) |s| {
            break :blk @as(Child, @ptrCast(@alignCast(s)));
        } else {
            break :blk null;
        }
    };

    switch (ptr.size) {
        .C => @compileError(@typeName(T) ++ " is a c ptr"),
        .One,
        => {
            if (@typeInfo(Child) == .Fn)
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
        .Float => math.sqrt(math.floatEps(T)),
        .ComptimeFloat => 1e-4,
        else => @compileError("floatEql is only supported for floats"),
    };

    return math.approxEqRel(T, a, b, tolerance);
}
