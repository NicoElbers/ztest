const std = @import("std");
const root = @import("root");
const util = @import("../ztest.zig").util;

pub inline fn isUsingZtestRunner() bool {
    return comptime blk: {
        const root_decls = @typeInfo(root).@"struct".decls;
        for (root_decls) |decl| {
            if (std.mem.eql(u8, "IsZtestRunner", decl.name)) {
                break :blk true;
            }
        }
        break :blk false;
    };
}
