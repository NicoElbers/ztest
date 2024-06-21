const std = @import("std");
const root = @import("root");

pub inline fn isUsingZtestRunner() bool {
    return comptime blk: {
        const root_decls = @typeInfo(root).Struct.decls;
        for (root_decls) |decl| {
            if (std.mem.eql(u8, "IsZtestRunner", decl.name)) {
                break :blk true;
            }
        }
        break :blk false;
    };
}

pub fn setUsingZtest() void {
    std.debug.assert(isUsingZtestRunner());

    root.clientUsingZtest = true;
}
