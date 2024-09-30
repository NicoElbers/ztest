pub const Poller = @import("poller.zig").Poller;
pub const Node = @import("node.zig").Node;
pub const Message = @import("Message.zig");

pub const NodeType = enum { client, server };

test {
    _ = Node(.server);
    _ = Node(.client);

    _ = Poller(.client);
    _ = Poller(.server);

    _ = @import("Message.zig");
}
