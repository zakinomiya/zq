const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;
const TokenType = lexer.TokenType;

const Nodes = std.ArrayList(Node);

const Value = union(enum) {
    string: []const u8,
    boolean: bool,
    integer: i64,
    float: f64,
    object: []Node,
    array: []Node,
    nul: bool,
};

const Key = struct {
    key: []const u8,
};

const Node = union(enum) {
    key: Key,
    value: Value,
};

const Parser = struct {
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

    fn parseArray(self: *Parser) ![]Node {
        try self.expectSkip(.BracketOpen);
        var arr = try self.allocator.create(Nodes);
        self.allocator.destroy(arr);
        arr.* = Nodes.init(self.allocator);
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

    fn parseValue(self: *Parser) anyerror!Node {
        const cur = self.current();
        var val = try self.allocator.create(Value);
        defer self.allocator.destroy(val);

        val.* = switch (cur.ty) {
            .String => Value{ .string = cur.raw },
            .Number => if (cur.num_val.? == .integer)
                Value{ .integer = cur.num_val.?.integer }
            else
                Value{ .float = cur.num_val.?.float },
            .CurlyBraceOpen => Value{ .object = try self.parseJson() },
            .BracketOpen => Value{ .array = try self.parseArray() },
            .Null => Value{ .nul = true },
            .Boolean => Value{ .boolean = if (std.mem.eql(u8, cur.raw, "true")) true else false },
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

        return Node{ .value = val.* };
    }

    fn parseNode(self: *Parser, arr: *Nodes) !void {
        const key = self.expect(.String) catch {
            std.log.err("no key found. object must be in the form of 'key: value'", .{});
            return error.NoKey;
        };

        std.log.err("key={s}", .{key.raw});
        try arr.append(Node{ .key = Key{ .key = key.raw } });
        try self.expectSkip(.Colon);
        try arr.append(try self.parseValue());
    }

    fn parseJson(self: *Parser) anyerror![]Node {
        try self.expectSkip(.CurlyBraceOpen);

        var arr = try self.allocator.create(Nodes);
        defer self.allocator.destroy(arr);
        arr.* = Nodes.init(self.allocator);
        defer arr.deinit();

        while (true) {
            try self.parseNode(arr);
            if (self.current().ty != .Comma) {
                break;
            }
            try self.expectSkip(.Comma);
        }

        try self.expectSkip(.CurlyBraceClose);
        return arr.toOwnedSlice();
    }

    // parse parses tokens and returns list of Node
    // caller own the returned memory
    fn parse(self: *Parser) ![]Node {
        return try self.parseJson();
    }
};

test "test parse" {
    const tokens = &[_]Token{
        .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
        .{ .ty = .String, .pos = 2, .raw = "hello" },
        .{ .ty = .Colon, .pos = 8, .raw = ":" },
        .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
        .{ .ty = .String, .pos = 2, .raw = "hello" },
        .{ .ty = .Colon, .pos = 8, .raw = ":" },
        .{ .ty = .CurlyBraceOpen, .pos = 0, .raw = "{" },
        .{ .ty = .String, .pos = 2, .raw = "hello" },
        .{ .ty = .Colon, .pos = 8, .raw = ":" },
        .{ .ty = .String, .pos = 10, .raw = "world" },
        .{ .ty = .CurlyBraceClose, .pos = 17, .raw = "}" },
        .{ .ty = .CurlyBraceClose, .pos = 17, .raw = "}" },
        .{ .ty = .CurlyBraceClose, .pos = 17, .raw = "}" },
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
    defer std.testing.allocator.free(nodes);
    free(nodes, std.testing.allocator);
}

fn free(nodes: []Node, allocator: std.mem.Allocator) void {
    for (nodes) |n| {
        switch (n) {
            .value => |v| switch (v) {
                .object,
                .array,
                => |vv| {
                    free(vv, allocator);
                    allocator.free(vv);
                },
                else => {},
            },
            .key => {},
        }
    }
}
