//! Pure input rules shared by the JSON API and the HTML forms. Each rule takes
//! the raw value (null = absent) and returns the trimmed value or an `Error`.
pub const Error = error{
    TitleRequired,
    TitleTooLong,
    DescriptionTooLong,
    ContentRequired,
    ContentTooLong,
    RoleInvalid,
    LanguageInvalid,
    InvalidText,
};

pub const max_title = 200;
pub const max_description = 2000;
pub const max_content = 5000;
pub const max_role = 64;
pub const max_language = 35;
pub const default_role = "person";
pub const default_language = "en";

const space = " \t\r\n";

/// Trims and checks UTF-8 (Postgres would reject it with a 500 otherwise).
fn clean(raw: ?[]const u8) Error![]const u8 {
    const s = std.mem.trim(u8, raw orelse "", space);
    if (!std.unicode.utf8ValidateSlice(s)) return error.InvalidText;
    return s;
}

/// Lengths are counted in code points.
fn tooLong(s: []const u8, max: usize) bool {
    return (std.unicode.utf8CountCodepoints(s) catch return true) > max;
}

pub fn title(raw: ?[]const u8) Error![]const u8 {
    const s = try clean(raw);
    if (s.len == 0) return error.TitleRequired;
    if (tooLong(s, max_title)) return error.TitleTooLong;
    return s;
}

/// May be empty.
pub fn description(raw: ?[]const u8) Error![]const u8 {
    const s = try clean(raw);
    if (tooLong(s, max_description)) return error.DescriptionTooLong;
    return s;
}

pub fn content(raw: ?[]const u8) Error![]const u8 {
    const s = try clean(raw);
    if (s.len == 0) return error.ContentRequired;
    if (tooLong(s, max_content)) return error.ContentTooLong;
    return s;
}

/// Blank defaults to "person".
pub fn role(raw: ?[]const u8) Error![]const u8 {
    const s = try clean(raw);
    if (s.len == 0) return default_role;
    if (tooLong(s, max_role)) return error.RoleInvalid;
    return s;
}

/// Blank defaults to "en".
pub fn languageOrDefault(raw: ?[]const u8) Error![]const u8 {
    const s = try clean(raw);
    return if (s.len == 0) default_language else language(s);
}

/// BCP 47-style tag: a 2-8 letter primary subtag, then `-` separated 1-8
/// character alphanumeric subtags ("en", "pt-BR", "zh-Hant-TW").
pub fn language(raw: ?[]const u8) Error![]const u8 {
    const s = try clean(raw);
    if (s.len == 0 or s.len > max_language) return error.LanguageInvalid;
    var parts = std.mem.splitScalar(u8, s, '-');
    const primary = parts.first();
    if (primary.len < 2 or primary.len > 8) return error.LanguageInvalid;
    for (primary) |c| if (!std.ascii.isAlphabetic(c)) return error.LanguageInvalid;
    while (parts.next()) |sub| {
        if (sub.len < 1 or sub.len > 8) return error.LanguageInvalid;
        for (sub) |c| if (!std.ascii.isAlphanumeric(c)) return error.LanguageInvalid;
    }
    return s;
}

/// Applies `rule` only when the value is present (for partial updates).
pub fn maybe(comptime rule: fn (?[]const u8) Error![]const u8, raw: ?[]const u8) Error!?[]const u8 {
    if (raw == null) return null;
    return try rule(raw);
}

pub fn message(err: Error) []const u8 {
    return switch (err) {
        error.TitleRequired => "Title is required.",
        error.TitleTooLong => "Title is too long (max 200 characters).",
        error.DescriptionTooLong => "Description is too long (max 2000 characters).",
        error.ContentRequired => "Content is required.",
        error.ContentTooLong => "Content is too long (max 5000 characters).",
        error.RoleInvalid => "Role must be at most 64 characters.",
        error.LanguageInvalid => "Language must be a code like en or pt-BR.",
        error.InvalidText => "Text must be valid UTF-8.",
    };
}

const std = @import("std");

test "rules trim, default and bound" {
    const t = std.testing;
    try t.expectEqualStrings("hi", try title("  hi \n"));
    try t.expectError(error.TitleRequired, title(null));
    try t.expectError(error.TitleRequired, title("   "));
    try t.expectError(error.TitleTooLong, title("x" ** 201));
    try t.expectEqualStrings("é" ** 200, try title("é" ** 200)); // 400 bytes, 200 code points
    try t.expectError(error.InvalidText, content("\xff"));
    try t.expectEqualStrings("person", try role(" "));
    try t.expectEqualStrings("en", try languageOrDefault(null));
    try t.expectEqualStrings("", try description(null));
    try t.expectEqual(@as(?[]const u8, null), try maybe(content, null));
    try t.expectError(error.ContentRequired, maybe(content, ""));
}

test "language codes" {
    const t = std.testing;
    for ([_][]const u8{ "en", "pt-BR", "zh-Hant-TW", "es-419" }) |ok| _ = try language(ok);
    for ([_][]const u8{ "", "e", "e1", "en_US", "en-", "-en", "toolongprimary", "en-waytoolongsub", "x" ** 36 }) |bad| {
        try t.expectError(error.LanguageInvalid, language(bad));
    }
}
