pub const Server = @import("Server.zig");
pub const ServerStreamer = @import("ServerStreamer.zig");

pub const Client = @import("Client.zig");
pub const ClientStreamer = @import("ClientStreamer.zig");

pub const Message = @import("Message.zig");

pub const special_message_start_key: [15]u8 = [_]u8{ 215, 217 } ++ "ZTESTIPCMSG".* ++ [_]u8{ 220, 235 };

test {
    _ = @import("Server.zig");
    _ = @import("ServerStreamer.zig");

    _ = @import("Client.zig");
    _ = @import("ClientStreamer.zig");

    _ = @import("Message.zig");
}
