test {
    const std = @import("std");
    const ztest = @import("ztest");

    const is_ztest = ztest.utils.isUsingZtestRunner();

    if (!is_ztest) {
        std.debug.print("\n\n SERVER IS NOT ZTEST RUNNER \n\n", .{});
        return;
    } else {
        ztest.utils.setUsingZtest();
        std.debug.print("\n\n SERVER IS ZTEST RUNNER \n\n", .{});
    }
}
