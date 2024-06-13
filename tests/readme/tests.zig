const basic_syntax = @import("basic_syntax.zig");
const extension = @import("extension.zig");

test {
    const testing = @import("std").testing;

    testing.refAllDecls(basic_syntax);
    testing.refAllDecls(extension);
}
