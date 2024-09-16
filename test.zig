const std = @import("std");
const posix = std.posix;
const assert = std.debug.assert;

const termios = posix.termios;
const File = std.fs.File;

const csi = [_]u8{ 0x1b, '[' };

pub fn main() !void {
    const stdout = std.io.getStdOut();

    const count = 1000;

    var total: u64 = 0;
    for (0..count) |_| {
        const start = try std.time.Instant.now();
        _ = try getTerminalWidth(stdout) orelse 80;
        const end = try std.time.Instant.now();
        total += end.since(start);
    }

    const width = try getTerminalWidth(stdout) orelse 80;

    std.debug.print("Getting terminal width took {d}ms on average\n", .{@divTrunc(total, std.time.ns_per_ms * count)});

    for (0..width) |_| {
        std.debug.print("-", .{});
    }
    std.debug.print("\n", .{});
}

pub fn getTerminalWidth(file: File) !?u16 {
    // Untested windows implementation
    // https://stackoverflow.com/a/23370070
    if (@import("builtin").os.tag == .windows) {
        const windows = std.os.windows;
        const kernel32 = windows.kernel32;

        const csbi: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        kernel32.GetConsoleScreenBufferInfo(file.handle, &csbi);

        const width: i16 = csbi.srWindow.Right - csbi.srWindow.Left + 1;
        assert(width >= 0);
        return @intCast(width);
    }

    // Use the existance of the termios struct as a heuristic to whether we can
    // query the terminal on this system
    if (!@hasDecl(posix, "termios"))
        return null;

    var buf: [64]u8 = undefined;

    // Format returned by `CSI 18 t` is `CSI 8 ; height ; width t`
    // https://terminalguide.namepad.de/seq/csi_st-18/
    const res = try terminalQuery("18t", file.handle, &buf);
    var spliterator = std.mem.splitScalar(u8, res, ';');

    assert(std.mem.eql(u8, spliterator.first(), [_]u8{0x1b} ++ "[8"));

    // Ignore the height
    assert(spliterator.next() != null);

    const width_buf_full = spliterator.next().?;
    const end_idx = std.mem.indexOfScalar(u8, width_buf_full, 't').?;
    const width_buf = width_buf_full[0..end_idx];
    return try std.fmt.parseInt(u16, width_buf, 10);
}

/// Your message will be prepended with CSI
fn terminalQuery(comptime msg: []const u8, fd: std.posix.fd_t, buf: []u8) ![]const u8 {
    const bak = try rawModeOn(fd);
    defer termiosReset(fd, bak) catch
        @panic("Terminal left in raw mode, please reset it");

    var written: usize = 0;
    while (written < csi.len + msg.len) {
        written += try std.posix.write(fd, csi ++ msg);
    }

    const res = try std.posix.read(fd, buf);
    return buf[0..res];
}

/// Your message will be prepended with CSI
fn terminalMessage(comptime msg: []const u8, fd: std.posix.fd_t) !void {
    const bak = try rawModeOn(fd);
    defer termiosReset(fd, bak) catch
        @panic("Terminal left in raw mode, please reset it");

    var written: usize = 0;
    while (written < csi.len + msg.len) {
        written += try std.posix.write(fd, csi ++ msg);
    }
}

fn rawModeOn(fd: std.posix.fd_t) !std.posix.termios {
    if (!@hasDecl(std.posix, "termios"))
        @compileError("Cannot enable raw mode on this architechture");

    var term = try std.posix.tcgetattr(fd);
    const copy = term;

    // zig fmt: off
    // Raw mode from man termios(3)
    term.iflag.BRKINT = false;
    term.iflag.ICRNL  = false;
    term.iflag.IGNBRK = false;
    term.iflag.IGNCR  = false;
    term.iflag.INLCR  = false;
    term.iflag.ISTRIP = false;
    term.iflag.IXON   = false;
    term.iflag.PARMRK = false;

    term.oflag.OPOST  = false;

    term.lflag.ECHO   = false;
    term.lflag.ECHONL = false;
    term.lflag.ICANON = false;
    term.lflag.IEXTEN = false;
    term.lflag.ISIG   = false;

    term.cflag.CSIZE  = .CS8;
    term.cflag.PARENB = false;
    // zig fmt: on

    try std.posix.tcsetattr(
        fd,
        std.posix.TCSA.FLUSH,
        term,
    );

    return copy;
}

fn termiosReset(fd: std.posix.fd_t, term: std.posix.termios) !void {
    try std.posix.tcsetattr(
        fd,
        std.posix.TCSA.FLUSH,
        term,
    );
}
