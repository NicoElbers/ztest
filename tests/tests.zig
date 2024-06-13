const readme = @import("readme/tests.zig");

test {
    const testing = @import("std").testing;

    testing.refAllDeclsRecursive(readme);
}
