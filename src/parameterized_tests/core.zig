const std = @import("std");

pub fn parameterizedTest(func: anytype, param_list: anytype) void {
    const func_type = @TypeOf(func);
    const func_info = @typeInfo(func_type);
    const param_list_info = @typeInfo(@TypeOf(param_list));

    if (func_info != .Fn)
        @compileError("func is expected to be a function");

    if (param_list_info != .Struct or !param_list_info.Struct.is_tuple)
        @compileError("param_list is expected to be a tuple of tuples");

    const func_param_types = extractFunctionTypes(func_type);

    inline for (param_list_info.Struct.fields) |param_tuple| {
        const param_tuple_info = @typeInfo(param_tuple.type);

        if (param_tuple_info != .Struct)
            @compileError("param_list must be a tuple of tuples");

        const tuple_param_types = extractStructFieldTypes(param_tuple_info.Struct.fields);

        if (func_param_types.len != tuple_param_types.len)
            @compileError(std.fmt.comptimePrint("Expected {d} parameters, but found {d}", .{
                func_param_types.len,
                tuple_param_types.len,
            }));

        inline for (func_param_types, tuple_param_types) |maybe_func_param, tuple_param| {
            if (maybe_func_param == null) continue; // null means anytype

            const func_param = maybe_func_param.?;

            if (func_param != tuple_param) {
                @compileError(std.fmt.comptimePrint(
                    "Expected parameters {any}, got {any}",
                    .{ func_param_types, tuple_param_types },
                ));
            }
        }
    }

    inline for (param_list) |thingy| {
        @call(.auto, func, thingy);
    }
}

pub fn extractFunctionTypes(comptime Function: type) []?type {
    const info = @typeInfo(Function);
    if (info != .Fn)
        @compileError("extractFunctionTypes expects a function type");

    const function_info = info.Fn;
    if (function_info.is_var_args)
        @compileError("Cannot extract types for variadic function");

    var argument_field_list: [function_info.params.len]?type = undefined;
    inline for (function_info.params, 0..) |arg, i| {
        argument_field_list[i] = arg.type;
    }

    return &argument_field_list;
}

pub fn extractStructFieldTypes(fields: []const std.builtin.Type.StructField) []type {
    var field_type_list: [fields.len]type = undefined;
    inline for (fields, 0..) |field, idx| {
        field_type_list[idx] = field.type;
    }

    return &field_type_list;
}

fn testFunc(first: u32, second: u64) void {
    std.debug.print("\n{d}\n", .{first + second});
}

test "simple" {
    var val: u64 = 123;
    _ = &val;

    parameterizedTest(testFunc, .{
        .{ @as(u32, 123), @as(u64, 432) },
        .{ @as(u32, 4325), val },
        .{ @as(u32, 4), @as(u64, 1) },
    });
}

fn testFunc2(first: anytype) void {
    std.debug.print("\n{any}\n", .{@typeInfo(@TypeOf(first))});
}

test "anytype" {
    var val: u32 = 342;
    _ = &val;

    parameterizedTest(testFunc2, .{
        .{123},
        .{@as(?type, u53)},
        .{@as(u32, 432)},
        .{val},
    });
}
