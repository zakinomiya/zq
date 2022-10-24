const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const printer = @import("printer.zig");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    var reader = std.io.getStdIn().reader();
    var buf = try arena.allocator().alloc(u8, 1000000);
    const i = try reader.readAll(buf);

    var tokenizer = try lexer.Tokenizer.init(arena.allocator(), buf[0 .. i + 1]);
    defer tokenizer.deinit();

    var tokens = try tokenizer.tokenize();
    defer arena.allocator().free(tokens);

    var p = try parser.Parser.init(arena.allocator(), tokens);
    defer p.deinit();
    var json = try p.parse();
    defer parser.freeJson(arena.allocator(), json);

    var pr = try printer.Printer.init(arena.allocator(), .{}, json);
    try pr.print();
}
