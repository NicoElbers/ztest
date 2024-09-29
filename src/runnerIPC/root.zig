pub const Server = @import("node.zig").Node(.server);
pub const Client = @import("node.zig").Node(.client);

pub const Poller = @import("poller.zig").Poller;
pub const Node = @import("node.zig").Node;

pub const Message = @import("Message.zig");

test {
    _ = Node(.server);
    _ = Node(.client);

    _ = Poller(.client);
    _ = Poller(.server);

    _ = @import("Message.zig");
}
