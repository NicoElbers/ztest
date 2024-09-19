clr_config: ColorConfig,
file: File,
ansi_support: bool,
alloc: Allocator,

/// Control sequence initializer for terminal control sequences
const csi = [_]u8{ 0x1b, '[' };

pub fn init(output_file: File, alloc: Allocator) Self {
    const clr_config = tty.detectConfig(output_file);
    const ansi_support = output_file.getOrEnableAnsiEscapeSupport();

    return Self{
        .clr_config = clr_config,
        .file = output_file,
        .ansi_support = ansi_support,
        .alloc = alloc,
    };
}

pub fn printFmt(self: Self, comptime fmt: []const u8, args: anytype) !void {
    try std.fmt.format(self.writer(), fmt, args);
}

pub fn writeAll(self: Self, bytes: []const u8) WriterError!void {
    return self.file.writeAll(bytes);
}

pub fn write(self: Self, bytes: []const u8) WriterError!void {
    return self.file.write(bytes);
}

pub fn writer(self: Self) Writer {
    return self.file.writer();
}

pub fn setColor(self: Self, color: Color) ColorError!void {
    return self.clr_config.setColor(self.writer(), color);
}

pub fn clearLine(self: Self) WriterError!void {
    assert(self.ansi_support);

    try self.writeAll("\x1b[G");
    try self.writeAll("\x1b[K");
}

// u15 because "<n> cannot be larger than 32,767 (maximum short value)"
// https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
pub fn moveUpLine(self: Self, count: u15) (WriterError || std.fmt.AllocPrintError)!void {
    assert(self.ansi_support);

    try self.printFmt("\x1b[{d}A", .{count});
}

// u15 because "<n> cannot be larger than 32,767 (maximum short value)"
// https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
pub fn moveDownLine(self: Self, count: u15) (WriterError || std.fmt.AllocPrintError)!void {
    assert(self.ansi_support);

    const move_str = try std.fmt.allocPrint(
        self.alloc,
        "\x1b[{d}E",
        .{count},
    );
    defer self.alloc.free(move_str);

    try self.writeAll(move_str);
}

pub fn moveToStartOfLine(self: Self) WriterError!void {
    try self.writeAll("\x1b[G");
}

pub fn saveCursorPosition(self: Self) WriterError!void {
    assert(self.ansi_support);

    try self.writeAll("\x1b[s");
}

pub fn loadCursorPosition(self: Self) WriterError!void {
    assert(self.ansi_support);

    try self.writeAll("\x1b[u");
}

pub fn clearBelow(self: Self) WriterError!void {
    assert(self.ansi_support);

    try self.writeAll("\x1b[0J");
}

pub fn getTerminalWidth(self: Self) !?u16 {
    const file = self.file;

    if (!file.isTty()) return null;

    // Untested windows implementation
    // https://stackoverflow.com/a/23370070
    if (@import("builtin").os.tag == .windows) {
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
fn terminalQuery(comptime msg: []const u8, fd: posix.fd_t, buf: []u8) ![]const u8 {
    const bak = try rawModeOn(fd);
    defer termiosReset(fd, bak) catch
        @panic("Terminal left in raw mode, please reset it");

    var written: usize = 0;
    while (written < csi.len + msg.len) {
        written += try posix.write(fd, csi ++ msg);
    }

    const res = try posix.read(fd, buf);
    return buf[0..res];
}

/// Your message will be prepended with CSI
fn terminalMessage(comptime msg: []const u8, fd: posix.fd_t) !void {
    const bak = try rawModeOn(fd);
    defer termiosReset(fd, bak) catch
        @panic("Terminal left in raw mode, please reset it");

    var written: usize = 0;
    while (written < csi.len + msg.len) {
        written += try posix.write(fd, csi ++ msg);
    }
}

/// Turns on terminal raw mode, see man 3 termios. The returned termios can be
/// passed to `termiosReset` to get your terminal functional again.
/// Asserts that `std.posix.termios` exists for the system.
fn rawModeOn(fd: posix.fd_t) !posix.termios {
    if (!@hasDecl(posix, "termios"))
        @compileError("Cannot enable raw mode on this architechture");

    var term = try posix.tcgetattr(fd);
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

    try posix.tcsetattr(
        fd,
        posix.TCSA.FLUSH,
        term,
    );

    return copy;
}

/// Resets termios to whatever you want.
fn termiosReset(fd: posix.fd_t, term: posix.termios) !void {
    try posix.tcsetattr(
        fd,
        posix.TCSA.FLUSH,
        term,
    );
}

const std = @import("std");
const windows = std.os.windows;
const posix = std.posix;
const tty = std.io.tty;

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const ColorConfig = tty.Config;
const Color = tty.Color;
const File = std.fs.File;
const Writer = File.Writer;

const WriterError = posix.WriteError;
const ColorError = WriterError || windows.SetConsoleTextAttributeError;

const Self = @This();
