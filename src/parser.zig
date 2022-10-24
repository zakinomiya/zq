const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;
const TokenType = lexer.TokenType;

const Objects = std.ArrayList(Object);

pub const Value = union(enum) {
    string: []const u8,
    boolean: bool,
    integer: i64,
    float: f64,
    object: []Object,
    array: []Value,
    nul: bool,
};

pub const Object = struct {
    key: []const u8,
    value: *Value,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    state: *State,
    tokens: []Token,

    const State = struct {
        pos: usize,
    };

    pub fn deinit(self: *Parser) void {
        self.allocator.destroy(self.state);
    }

    pub fn init(allocator: std.mem.Allocator, tokens: []Token) !Parser {
        var state = try allocator.create(State);
        state.* = State{ .pos = 0 };

        return Parser{
            .allocator = allocator,
            .tokens = tokens,
            .state = state,
        };
    }

    fn current(self: *Parser) Token {
        return self.tokens[self.state.pos];
    }

    fn expect(self: *Parser, ty: TokenType) !Token {
        const cur = self.current();
        if (ty != cur.ty) {
            std.log.err("expected type {} but given {}", .{ ty, cur.ty });
            return error.ExpectError;
        }

        self.state.pos += 1;
        return cur;
    }

    fn expectSkip(self: *Parser, ty: TokenType) !void {
        _ = try self.expect(ty);
    }

    fn parseArray(self: *Parser) ![]Value {
        try self.expectSkip(.BracketOpen);
        var arr = try self.allocator.create(std.ArrayList(Value));
        defer self.allocator.destroy(arr);
        arr.* = std.ArrayList(Value).init(self.allocator);
        defer arr.deinit();

        while (true) {
            try arr.append(try self.parseValue());
            if (self.current().ty != .Comma) {
                break;
            }
            try self.expectSkip(.Comma);
        }

        try self.expectSkip(.BracketClose);
        return arr.toOwnedSlice();
    }

    fn parseValue(self: *Parser) anyerror!Value {
        const cur = self.current();
        var val = switch (cur.ty) {
            .String => Value{ .string = cur.raw },
            .Number => if (cur.num_val.? == .integer)
                Value{ .integer = cur.num_val.?.integer }
            else
                Value{ .float = cur.num_val.?.float },
            .CurlyBraceOpen => Value{ .object = try self.parseJson() },
            .BracketOpen => Value{ .array = try self.parseArray() },
            .Null => Value{ .nul = true },
            .Boolean => if (std.mem.eql(u8, cur.raw, "true"))
                Value{ .boolean = true }
            else
                Value{ .boolean = false },
            else => {
                std.log.err("expected start of value at position {d} but type is {}", .{ cur.pos, cur.ty });
                return error.InvalidSyntax;
            },
        };

        switch (cur.ty) {
            .String,
            .Number,
            .Null,
            .Boolean,
            => {
                self.state.pos += 1;
            },
            else => {},
        }

        return val;
    }

    fn parseObject(self: *Parser, arr: *Objects) !void {
        const key = self.expect(.String) catch {
            std.log.err("no key found. object must be in the form of 'key: value'", .{});
            return error.NoKey;
        };

        try self.expectSkip(.Colon);
        var val = try self.allocator.create(Value);
        val.* = try self.parseValue();
        var node = Object{
            .key = key.raw,
            .value = val,
        };
        try arr.append(node);
    }

    fn parseJson(self: *Parser) anyerror![]Object {
        try self.expectSkip(.CurlyBraceOpen);

        var arr = try self.allocator.create(Objects);
        defer self.allocator.destroy(arr);
        arr.* = Objects.init(self.allocator);
        defer arr.deinit();

        while (true) {
            try self.parseObject(arr);
            if (self.current().ty != .Comma) {
                break;
            }
            try self.expectSkip(.Comma);
        }

        try self.expectSkip(.CurlyBraceClose);
        return arr.toOwnedSlice();
    }

    /// parse parses tokens and returns list of Object.
    /// Caller must call freeObjects on result
    pub fn parse(self: *Parser) ![]Object {
        return try self.parseJson();
    }
};

/// freeObjects recursively frees all the nodes allocated by Parser.parse.
pub fn freeObjects(allocator: std.mem.Allocator, nodes: []Object) void {
    defer allocator.free(nodes);
    for (nodes) |n| {
        defer allocator.destroy(n.value);
        switch (n.value.*) {
            .array => |v| {
                freeValues(allocator, v);
            },
            .object => |v| {
                freeObjects(allocator, v);
            },
            else => {},
        }
    }
}

fn freeValues(allocator: std.mem.Allocator, values: []Value) void {
    defer allocator.free(values);
    for (values) |val| {
        switch (val) {
            .array => |v| {
                freeValues(allocator, v);
            },
            .object => |v| {
                freeObjects(allocator, v);
            },
            else => {},
        }
    }
}

test "test parse" {
    const tokens = &[_]Token{
        .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
        .{ .ty = .String, .pos = 0, .raw = "hello" },
        .{ .ty = .Colon, .pos = 0, .raw = ":" },
        .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
        .{ .ty = .String, .pos = 0, .raw = "hello" },
        .{ .ty = .Colon, .pos = 0, .raw = ":" },
        .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
        .{ .ty = .String, .pos = 0, .raw = "hello" },
        .{ .ty = .Colon, .pos = 0, .raw = ":" },
        .{ .ty = .String, .pos = 0, .raw = "world" },
        .{ .ty = .CurlyBraceClose, .pos = 0, .raw = "}" },
        .{ .ty = .CurlyBraceClose, .pos = 0, .raw = "}" },
        .{ .ty = .CurlyBraceClose, .pos = 0, .raw = "}" },
    };

    var toks = try std.testing.allocator.alloc(Token, tokens.len);
    defer std.testing.allocator.free(toks);
    for (tokens) |tok, i| {
        toks[i] = tok;
    }

    var parser = try Parser.init(
        std.testing.allocator,
        toks,
    );
    defer parser.deinit();

    const nodes = try parser.parse();
    defer freeObjects(std.testing.allocator, nodes);
}
