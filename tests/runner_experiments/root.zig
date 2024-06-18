test {
    const root = @import("root");
    const std = @import("std");

    var is_ztest = false;

    const root_decls = comptime std.meta.declarations(root);
    inline for (root_decls) |decl| {
        if (std.mem.eql(u8, "IsZtestRunner", decl.name)) {
            is_ztest = true;
            break;
        }
    }

    if (!is_ztest) {
        std.debug.print("\n\n IS NOT ZTEST \n\n", .{});
        return;
    } else {
        std.debug.print("\n\n IS ZTEST \n\n", .{});
    }
}
