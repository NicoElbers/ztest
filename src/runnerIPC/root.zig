pub const Server = @import("Server.zig");
pub const Client = @import("Client.zig");

pub const Poller = @import("poller.zig").Poller;

pub const Message = @import("Message.zig");

test {
    _ = @import("Server.zig");
    _ = @import("Client.zig");

    _ = Poller(.client);
    _ = Poller(.server);

    _ = @import("Message.zig");
}
