const std = @import("std");
const lexer = @import("./lexer.zig");
const Token = lexer.Token;

const Printer = struct {
    allocator: std.mem.Allocator,
    tokens: []Token,
    config: PrinterConfig,
    indent_char: u8,
    writer: std.fs.File.Writer,

    pub const PrinterConfig = struct {
        pretty: bool = true,
        indent_length: usize = 2,
        indent_mode: enum {
            Space,
            Tab,
        } = .Space,
        output: enum {
            Stdio,
            File,
        } = .Stdio,
        output_name: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator, printer_config: PrinterConfig, tokens: []Token) !Printer {
        var f = switch (printer_config.output) {
            .Stdio => std.io.getStdOut(),
            .File => try std.fs.createFileAbsolute(printer_config.output_name.?, std.fs.File.CreateFlags{}),
        };
        return Printer{
            .allocator = allocator,
            .tokens = tokens,
            .config = printer_config,
            .indent_char = if (printer_config.indent_mode == .Space) ' ' else '\t',
            .writer = f.writer(),
        };
    }

    fn writeByteIfPretty(self: Printer, b: u8) !void {
        if (!self.config.pretty) {
            return;
        }
        try self.writer.writeByte(b);
    }

    fn writeString(self: Printer, b: []const u8) !void {
        try self.writer.writeByte('"');
        _ = try self.writer.write(b);
        try self.writer.writeByte('"');
    }

    fn writeIndent(self: Printer, nest_depth: usize) !void {
        if (!self.config.pretty) {
            return;
        }

        const indent = self.config.indent_length * nest_depth;
        try self.writer.writeByteNTimes(self.indent_char, indent);
    }

    pub fn print(self: Printer) !void {
        var nest_depth: usize = 0;
        for (self.tokens) |tok| {
            try self.writeIndent(nest_depth);
            switch (tok.ty) {
                .CurlyBraceOpen,
                .CurlyBraceClose,
                .BracketOpen,
                .BracketClose,
                => {
                    try self.writer.writeByte(tok.raw[0]);
                    try self.writeByteIfPretty('\n');
                },
                .Colon => {
                    try self.writer.writeByte(tok.raw[0]);
                },
                .String => {
                    try self.writeString(tok.raw);
                    // _ = try self.writeByteIfPretty('\n');
                },
                .Boolean,
                .Comma,
                .Null,
                .Number,
                => {
                    _ = try self.writer.write(tok.raw);
                    try self.writeByteIfPretty('\n');
                },
            }

            // manage nest
            switch (tok.ty) {
                .BracketOpen,
                .CurlyBraceOpen,
                => {
                    nest_depth += 1;
                },
                .BracketClose,
                .CurlyBraceClose,
                => {
                    nest_depth -= 1;
                },
                else => {},
            }
        }
    }
};

// pub fn main() !void {
//     var tokens = &[_]Token{
//         Token.tok_curly_brace_open,
//         Token.newString("hello"),
//         Token.tok_colon,
//         Token.tok_curly_brace_open,
//         Token.newString("hello"),
//         Token.tok_colon,
//         Token.newString("world"),
//         Token.tok_curly_brace_close,
//         Token.tok_curly_brace_close,
//     };
//     var printer = try Printer.init(std.testing.allocator, Printer.PrinterConfig{}, tokens);
//     try printer.print();
// }

test "test printer" {}
