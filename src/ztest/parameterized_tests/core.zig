const std = @import("std");
const ztest = @import("../ztest.zig");
const IPC = @import("IPC");
const util = ztest.util;
const runner = util.RunnerInfo;

const Client = IPC.Client;

const assert = std.debug.assert;

pub fn parameterizedTest(comptime func: anytype, param_list: anytype) !void {
    verifyArguments(@TypeOf(func), @TypeOf(param_list));

    var client = IPC.Client.init(ztest.allocator);

    var any_failed = false;
    inline for (param_list) |param_tuple| {
        if (util.isUsingZtestRunner) {
            // TODO: Consider sending over the type (@typeInfo) over instead of
            // this, that way the runner has a big more information. We'd also have
            // to send over the type name, so I'm not 100% sure this is really useful
            // but we can see
            var buf: [1024]u8 = undefined;
            const args_str = try makeArgsStr(&buf, param_tuple);
            try client.serveParameterizedStart(args_str);
        }

        const res = util.callAnyFunction(func, param_tuple);

        _ = res catch |err| switch (@as(anyerror, @errorCast(err))) {
            error.ZigSkipTest => {
                if (util.isUsingZtestRunner) {
                    try client.serveParameterizedSkipped();
                }
            },
            else => {
                any_failed = true;

                if (util.isUsingZtestRunner) {
                    try client.serveParameterizedError(@errorName(err));
                }
            },
        };
    }

    if (any_failed) {
        if (@errorReturnTrace()) |st| {
            std.debug.print("Stack trace:\n", .{});
            std.debug.dumpStackTrace(st.*);
            std.debug.print("\n", .{});
        }
    }

    if (util.isUsingZtestRunner) {
        try client.serveParameterizedComplete();
    }

    if (any_failed) {
        return error.ParameterizedTestFailure;
    }
}

/// Assumes param_tuple is a valid param tuple
fn makeArgsStr(buf: []u8, param_tuple: anytype) ![]const u8 {
    const T = @TypeOf(param_tuple);
    const info = @typeInfo(T).@"struct";

    var fbs = std.io.fixedBufferStream(buf);
    const writer = fbs.writer().any();

    try writer.writeAll("{ ");

    inline for (info.fields, param_tuple) |field, param| {
        const specifier = fmtSpecifier(field.type);

        if (specifier) |s| {
            const fmt = "{" ++ s ++ "}, ";

            try std.fmt.format(writer, fmt, .{param});
        } else {
            try writer.writeAll(@typeName(field.type) ++ ", ");
        }
    }

    if (info.fields.len > 0) {
        try fbs.seekBy(-2);
    }
    try writer.writeAll(" }");

    return fbs.getWritten();
}

inline fn fmtSpecifier(comptime T: type) ?[:0]const u8 {
    const ANY = "any";

    switch (@typeInfo(T)) {
        .pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .array => fmtSpecifier(ptr_info.child),
                else => return "*",
            },
            .Many, .C => return "*",
            .Slice => {
                if (ptr_info.child == u8 and ptr_info.is_const) {
                    return "s";
                } else {
                    return ANY;
                }
            },
        },
        .optional => |info| return "?" ++ (fmtSpecifier(info.child) orelse return null),
        .error_union => |info| return "!" ++ (fmtSpecifier(info.payload) orelse return null),
        .error_set => return "!",

        .int,
        .comptime_int,
        .float,
        .comptime_float,
        => return "d",

        .array,
        .type,
        .void,
        .bool,
        .@"struct",
        .null,
        .@"enum",
        .@"union",
        .vector,
        .enum_literal,
        => return ANY,

        else => return null,
    }
    unreachable;
}

fn verifyArguments(comptime func_type: type, comptime param_list: type) void {
    const func_info = @typeInfo(func_type);
    const param_list_info = @typeInfo(param_list);

    if (func_info != .@"fn")
        @compileError("func is expected to be a function");

    if (param_list_info != .@"struct" or !param_list_info.@"struct".is_tuple)
        @compileError("param_list is expected to be a tuple of tuples");

    const func_param_types = extractFunctionTypes(func_type);

    inline for (param_list_info.@"struct".fields) |param_tuple| {
        const param_tuple_info = @typeInfo(param_tuple.type);

        if (param_tuple_info != .@"struct")
            @compileError("param_list must be a tuple of tuples");

        const tuple_param_types = extractStructFieldTypes(param_tuple_info.@"struct".fields);

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
}

pub fn extractFunctionTypes(comptime Function: type) []?type {
    const info = @typeInfo(Function);
    if (info != .@"fn")
        @compileError("extractFunctionTypes expects a function type");

    const function_info = info.@"fn";
    if (function_info.is_var_args)
        @compileError("Cannot extract types for variadic function");

    var argument_field_list: [function_info.params.len]?type = undefined;
    inline for (function_info.params, 0..) |arg, i| {
        argument_field_list[i] = arg.type;
    }

    return &argument_field_list;
}

// TEST: make sure that this doesn't get overriden when the stack changes
pub fn extractStructFieldTypes(fields: []const std.builtin.Type.StructField) []type {
    var field_type_list: [fields.len]type = undefined;
    inline for (fields, 0..) |field, idx| {
        field_type_list[idx] = field.type;
    }

    return &field_type_list;
}

// FIXME: Remove tests from here, they serve no purpose
// TEST: instead create more minimal tests that show off the specific function
fn testFunc(first: u32, second: u64) void {
    _ = first + second;
}

test "simple" {
    var val: u64 = 123;
    _ = &val;

    try parameterizedTest(testFunc, .{
        .{ @as(u32, 123), @as(u64, 432) },
        .{ @as(u32, 4325), val },
        .{ @as(u32, 4), @as(u64, 1) },
    });
}

fn testFunc2(first: anytype) void {
    _ = first;
}

test "anytype" {
    var val: u32 = 342;
    _ = &val;

    try parameterizedTest(testFunc2, .{
        .{123},
        .{@as(?type, u53)},
        .{@as(u32, 432)},
        .{val},
    });
}

fn testFunc3(comptime T: type) void {
    _ = T;
}

test "comptime" {
    try parameterizedTest(testFunc3, .{
        .{u32},
    });
}
