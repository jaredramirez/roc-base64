//! std.base64 from the Zig standard library
const std = @import("std");
const b64 = std.base64.standard;

fn best(io: std.Io, iters: usize, ctx: anytype, comptime f: fn (@TypeOf(ctx)) anyerror!void) !i96 {
    try f(ctx);
    try f(ctx); // warm up
    var min: i96 = std.math.maxInt(i96);
    for (0..iters) |_| {
        const start = std.Io.Timestamp.now(io, .awake);
        try f(ctx);
        const ns = start.untilNow(io, .awake).nanoseconds;
        if (ns < min) min = ns;
    }
    return min;
}

const Ctx = struct { gpa: std.mem.Allocator, data: []const u8, text: []const u8 };

// Each run allocates its output, like the other languages' APIs
fn encode(ctx: Ctx) anyerror!void {
    const out = try ctx.gpa.alloc(u8, b64.Encoder.calcSize(ctx.data.len));
    defer ctx.gpa.free(out);
    std.mem.doNotOptimizeAway(b64.Encoder.encode(out, ctx.data));
}

fn decode(ctx: Ctx) anyerror!void {
    const out = try ctx.gpa.alloc(u8, try b64.Decoder.calcSizeForSlice(ctx.text));
    defer ctx.gpa.free(out);
    try b64.Decoder.decode(out, ctx.text);
    std.mem.doNotOptimizeAway(out);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const size = try std.fmt.parseInt(usize, args[1], 10);
    const iters = try std.fmt.parseInt(usize, args[2], 10);
    const gpa = std.heap.c_allocator;

    const data = try gpa.alloc(u8, size);
    for (data, 0..) |*byte, i| byte.* = @intCast((i * 31 + 7) % 256);
    const text = try gpa.alloc(u8, b64.Encoder.calcSize(size));
    _ = b64.Encoder.encode(text, data);
    const round = try gpa.alloc(u8, try b64.Decoder.calcSizeForSlice(text));
    try b64.Decoder.decode(round, text);
    if (!std.mem.eql(u8, round, data)) return error.RoundTripFailed;

    const ctx: Ctx = .{ .gpa = gpa, .data = data, .text = text };
    const enc = try best(init.io, iters, ctx, encode);
    const dec = try best(init.io, iters, ctx, decode);
    var buf: [64]u8 = undefined;
    try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.bufPrint(&buf, "{d} {d}\n", .{ enc, dec }));
}
