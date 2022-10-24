const std = @import("std");
const lexer = @import("./lexer.zig");
const Token = lexer.Token;
const parser = @import("./parser.zig");
const Object = parser.Object;
const Value = parser.Value;

pub const Printer = struct {
    allocator: std.mem.Allocator,
    toplevel: Object,
    config: PrinterConfig,
    indent_char: u8,
    writer: std.fs.File.Writer,
    state: *State,

    pub const State = struct {
        nest_depth: u8,

        pub fn nestDown(self: *State) void {
            self.nest_depth += 1;
        }

        pub fn nestUp(self: *State) void {
            self.nest_depth -= 1;
        }
    };

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

    pub fn deinit(self: Printer) void {
        self.allocator.destroy(self.state);
    }

    pub fn init(allocator: std.mem.Allocator, printer_config: PrinterConfig, toplevel: Object) !Printer {
        var f = switch (printer_config.output) {
            .Stdio => std.io.getStdOut(),
            .File => try std.fs.createFileAbsolute(printer_config.output_name.?, std.fs.File.CreateFlags{}),
        };
        var s = try allocator.create(State);
        s.* = State{ .nest_depth = 0 };

        return Printer{
            .allocator = allocator,
            .toplevel = toplevel,
            .config = printer_config,
            .indent_char = if (printer_config.indent_mode == .Space) ' ' else '\t',
            .writer = f.writer(),
            .state = s,
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

    fn writeIndent(self: Printer) !void {
        if (!self.config.pretty) {
            return;
        }

        const indent = self.config.indent_length * self.state.nest_depth;
        try self.writer.writeByteNTimes(self.indent_char, indent);
    }

    fn printValue(self: Printer, val: *Value) anyerror!void {
        switch (val.*) {
            .boolean,
            .integer,
            .float,
            .nul,
            => |v| {
                _ = try self.writer.write(v);
            },
            .string => |v| {
                try self.writeString(v);
            },
            .object => |v| {
                try self.printObject(v);
            },
            .array => |v| {
                try self.printArray(v);
            },
        }
    }

    fn printArray(self: Printer, values: []Value) !void {
        // [
        try self.writer.writeByte('[');
        try self.writeByteIfPretty('\n');
        self.state.nestDown();

        for (values) |*val, i| {
            // value(,)
            try self.writeIndent();
            try self.printValue(val);
            if (i < values.len - 1) {
                try self.writer.writeByte(',');
            }
            try self.writeByteIfPretty('\n');
        }

        // ]
        self.state.nestUp();
        try self.writeIndent();
        try self.writer.writeByte(']');
    }

    fn printKeyValue(self: Printer, obj: Object) !void {
        // key: value(,)
        try self.writeIndent();
        try self.writeString(obj.key);
        try self.writer.writeByte(':');
        try self.writeByteIfPretty(' ');
        try self.printValue(obj.value);
    }

    fn printObject(self: Printer, obj: []Object) !void {
        // {
        try self.writer.writeByte('{');
        try self.writeByteIfPretty('\n');
        self.state.nestDown();

        for (obj) |o, i| {
            try self.printKeyValue(o);
            if (i < obj.len - 1) {
                try self.writer.writeByte(',');
            }
            try self.writeByteIfPretty('\n');
        }

        // }
        self.state.nestUp();
        try self.writeIndent();
        try self.writer.writeByte('}');
    }

    pub fn print(self: Printer) !void {
        switch (self.toplevel.value.*) {
            .object => |v| try self.printObject(v),
            .array => |v| try self.printArray(v),
            else => return error.InvalidToplevelObj,
        }
        try self.writeByteIfPretty('\n');
    }
};
