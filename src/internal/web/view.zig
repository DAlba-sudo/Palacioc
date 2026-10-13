//! View model of the two-pane shell (html/shell.zmpl) and its builder. Every
//! field is preformatted for printing; the builder is pure (no DB, no HTTP) and
//! allocates in the request arena. "" means unset for strings.
pub const max_cards = 48;
const snippet_len = 60;

/// Which edit form the work pane shows instead of the plain translation form.
pub const Edit = union(enum) { none, message, translation: i32 };

/// The request state carried in `/ui/conversation/:id?sel=&leaf=&edit=&q=`.
pub const State = struct {
    conv: i32 = 0,
    sel: ?i32 = null,
    leaf: ?i32 = null,
    /// Branch switch: show the route through this message.
    via: ?i32 = null,
    /// Language the chat shows ("" = source); only a code the conversation has translations in is kept.
    lang: []const u8 = "",
    edit: Edit = .none,
    q: []const u8 = "",
};

/// "m" (the selected message) or "t<id>" (a translation); anything else is none.
pub fn parseEdit(s: []const u8) Edit {
    if (std.mem.eql(u8, s, "m")) return .message;
    if (s.len > 1 and s[0] == 't') {
        if (contract.parseId(s[1..])) |id| return .{ .translation = id };
    }
    return .none;
}

/// Appends `lang=<code>` (when set) after `sep`, which then becomes '&'. Codes are validated, so no escaping.
fn langParam(w: *std.Io.Writer, sep: *u8, lang: []const u8) !void {
    if (lang.len == 0) return;
    try w.print("{c}lang={s}", .{ sep.*, lang });
    sep.* = '&';
}

/// `/ui/conversation/<conv>` with `sel`, `leaf`, `edit` and `lang` as query params when set.
pub fn url(a: std.mem.Allocator, conv: i32, sel: ?i32, leaf: ?i32, edit: Edit, lang: []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(a);
    const w = &aw.writer;
    try w.print("/ui/conversation/{d}", .{conv});
    var sep: u8 = '?';
    if (sel) |s| {
        try w.print("{c}sel={d}", .{ sep, s });
        sep = '&';
    }
    if (leaf) |l| {
        try w.print("{c}leaf={d}", .{ sep, l });
        sep = '&';
    }
    switch (edit) {
        .none => {},
        .message => {
            try w.print("{c}edit=m", .{sep});
            sep = '&';
        },
        .translation => |t| {
            try w.print("{c}edit=t{d}", .{ sep, t });
            sep = '&';
        },
    }
    try langParam(w, &sep, lang);
    return aw.written();
}

/// `/ui/conversation/<conv>?via=<message>[&sel=<message>][&lang=..]`: a branch switch.
pub fn viaUrl(a: std.mem.Allocator, conv: i32, via: i32, sel: ?i32, lang: []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(a);
    const w = &aw.writer;
    try w.print("/ui/conversation/{d}?via={d}", .{ conv, via });
    var sep: u8 = '&';
    if (sel) |s| try w.print("&sel={d}", .{s});
    try langParam(w, &sep, lang);
    return aw.written();
}

/// `?sel=..&leaf=..&lang=..` for the mutation endpoints ("" when all are unset).
pub fn stateQuery(a: std.mem.Allocator, sel: ?i32, leaf: ?i32, lang: []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(a);
    const w = &aw.writer;
    var sep: u8 = '?';
    if (sel) |s| {
        try w.print("{c}sel={d}", .{ sep, s });
        sep = '&';
    }
    if (leaf) |l| {
        try w.print("{c}leaf={d}", .{ sep, l });
        sep = '&';
    }
    try langParam(w, &sep, lang);
    return aw.written();
}

pub const RoleOpt = struct { name: []const u8 };

/// Distinct roles used in the conversation, most recently used first, always
/// ending with the default role when it has not been used.
pub fn roleSuggestions(a: std.mem.Allocator, messages: []const types.Message) ![]const RoleOpt {
    var out: std.ArrayList(RoleOpt) = .empty;
    var i = messages.len;
    while (i > 0) {
        i -= 1;
        try addRole(a, &out, messages[i].role);
    }
    try addRole(a, &out, validate.default_role);
    return out.items;
}

fn addRole(a: std.mem.Allocator, out: *std.ArrayList(RoleOpt), role: []const u8) !void {
    for (out.items) |r| if (std.mem.eql(u8, r.name, role)) return;
    try out.append(a, .{ .name = role });
}

/// At most `snippet_len` code points, with an ellipsis when cut.
fn snippet(a: std.mem.Allocator, s: []const u8, max: usize) ![]const u8 {
    var it = (std.unicode.Utf8View.init(s) catch return "").iterator();
    var n: usize = 0;
    while (it.nextCodepointSlice()) |_| {
        if (n == max) return std.fmt.allocPrint(a, "{s}...", .{s[0..it.i]});
        n += 1;
    }
    return s;
}

/// A few common codes offered next to the languages already in use.
const common_languages = [_][]const u8{ "en", "es", "fr", "de", "it", "pt", "ja", "zh", "ko", "ru" };

/// Languages used by this conversation's translations (first use first), its
/// source language, then common codes; deduplicated.
pub fn languageSuggestions(a: std.mem.Allocator, translations: []const types.Translation, source: []const u8) ![]const RoleOpt {
    var out: std.ArrayList(RoleOpt) = .empty;
    for (translations) |t| try addRole(a, &out, t.language);
    if (source.len > 0) try addRole(a, &out, source);
    for (common_languages) |c| try addRole(a, &out, c);
    return out.items;
}

/// Role the composer starts with for a reply to `target_role`: with exactly two
/// roles in the conversation, the other one; otherwise the target's role.
pub fn defaultRole(messages: []const types.Message, target_role: ?[]const u8) []const u8 {
    const target = target_role orelse return validate.default_role;
    var other: ?[]const u8 = null;
    var distinct: usize = 0;
    for (messages, 0..) |m, i| {
        for (messages[0..i]) |prev| {
            if (std.mem.eql(u8, prev.role, m.role)) break;
        } else {
            distinct += 1;
            if (!std.mem.eql(u8, m.role, target)) other = m.role;
        }
    }
    if (distinct == 2) {
        if (other) |o| return o;
    }
    return target;
}

/// "role-0".."role-3" by order of first appearance, so each speaker keeps a side/colour.
fn roleClass(messages: []const types.Message, role: []const u8) []const u8 {
    var n: usize = 0;
    for (messages, 0..) |m, i| {
        for (messages[0..i]) |prev| {
            if (std.mem.eql(u8, prev.role, m.role)) break;
        } else {
            if (std.mem.eql(u8, m.role, role)) break;
            n += 1;
        }
    }
    return switch (n % 4) {
        0 => "r0",
        1 => "r1",
        2 => "r2",
        else => "r3",
    };
}

/// The language to show: the stored spelling of `raw` when this conversation has a
/// translation in it, else "" (source).
pub fn effectiveLang(translations: []const types.Translation, raw: []const u8) []const u8 {
    if (raw.len == 0) return "";
    for (translations) |t| {
        if (std.ascii.eqlIgnoreCase(t.language, raw)) return t.language;
    }
    return "";
}

pub const Pick = struct {
    /// Newest translation of the message in the language (by `updated_at`, then id).
    tr: ?types.Translation = null,
    /// How many translations the message has in the language.
    count: usize = 0,
};

pub fn pickTranslation(translations: []const types.Translation, message_id: i32, lang: []const u8) Pick {
    var p: Pick = .{};
    for (translations) |t| {
        if (t.message_id != message_id or !std.mem.eql(u8, t.language, lang)) continue;
        p.count += 1;
        if (p.tr) |best| {
            if (t.updated_at < best.updated_at or (t.updated_at == best.updated_at and t.id < best.id)) continue;
        }
        p.tr = t;
    }
    return p;
}

pub const LangOpt = struct { code: []const u8, label: []const u8, id: []const u8, checked: []const u8 };

/// "Source (<code>)" first, then each language with a translation in first-use order.
pub fn languageOptions(a: std.mem.Allocator, translations: []const types.Translation, source: []const u8, active: []const u8) ![]const LangOpt {
    var out: std.ArrayList(LangOpt) = .empty;
    try out.append(a, .{
        .code = "",
        .label = try std.fmt.allocPrint(a, "Source ({s})", .{source}),
        .id = "lang-opt-source",
        .checked = if (active.len == 0) "checked" else "",
    });
    for (translations, 0..) |t, i| {
        for (translations[0..i]) |prev| {
            if (std.mem.eql(u8, prev.language, t.language)) break;
        } else try out.append(a, .{
            .code = t.language,
            .label = t.language,
            .id = try std.fmt.allocPrint(a, "lang-opt-{s}", .{t.language}),
            .checked = if (std.mem.eql(u8, t.language, active)) "checked" else "",
        });
    }
    return out.items;
}

pub const SibOpt = struct { label: []const u8, url: []const u8, cls: []const u8, current: []const u8 };

pub const Bubble = struct {
    id: i32,
    role: []const u8,
    content: []const u8,
    cls: []const u8,
    role_cls: []const u8,
    selected: bool,
    current: []const u8,
    select_url: []const u8,
    edit_url: []const u8,
    delete_url: []const u8,
    delete_confirm: []const u8,
    /// Fork bar shown before this bubble when it has siblings.
    fork: bool,
    fork_label: []const u8,
    prev_url: []const u8,
    next_url: []const u8,
    prev_attr: []const u8,
    next_attr: []const u8,
    sibs: []const SibOpt,
    /// Translation count as a badge text ("2"), or "".
    badge: []const u8,
    badge_title: []const u8,
    /// `lang` of the text element, the "source" tag of an untranslated fallback and the "+N" extra-alternatives mark.
    text_lang: []const u8,
    src_tag: []const u8,
    more: []const u8,
    title: []const u8,
};

pub const Card = struct {
    id: i32,
    title: []const u8,
    description: []const u8,
    language: []const u8,
    cls: []const u8,
    open_url: []const u8,
    delete_url: []const u8,
};

pub const TrRow = struct { id: i32, language: []const u8, content: []const u8, cls: []const u8, edit_url: []const u8, delete_url: []const u8 };

pub const LangGroup = struct { code: []const u8, count: []const u8, rows: []const TrRow };

pub const Shell = struct {
    /// Mobile pane shown first: "chat" or "work".
    pane: []const u8,

    // Chat pane.
    has_conv: bool,
    chat_lang: []const u8,
    source_code: []const u8,
    has_toggle: bool,
    lang_opts: []const LangOpt,
    toggle_url: []const u8,
    composer_lang: []const u8,
    conv_title: []const u8,
    bubbles: []const Bubble,
    empty_chat: bool,
    empty_text: []const u8,
    composer_action: []const u8,
    /// Hidden form values, so the persistent composer always posts the current state.
    composer_sel: []const u8,
    composer_leaf: []const u8,
    composer_role: []const u8,
    composer_err: []const u8,
    composer_hidden: []const u8,
    roles: []const RoleOpt,
    chip: bool,
    chip_label: []const u8,
    chip_text: []const u8,
    chip_clear_url: []const u8,

    // Work pane modes (exactly one is true).
    mode_cards: bool,
    mode_translate: bool,
    mode_edit_msg: bool,

    // Conversations mode.
    q: []const u8,
    search_url: []const u8,
    cards: []const Card,
    cards_empty: bool,
    form: forms.ConversationForm,
    new_open: []const u8,

    // Translation mode (also holds the edit-translation form).
    back_url: []const u8,
    cancel_url: []const u8,
    sel_role: []const u8,
    sel_content: []const u8,
    sel_role_cls: []const u8,
    tr_edit: bool,
    tr_action: []const u8,
    tr_heading: []const u8,
    tr_button: []const u8,
    tr_language: []const u8,
    tr_content: []const u8,
    err_tr_language: []const u8,
    err_tr_content: []const u8,
    notice: []const u8,
    langs: []const RoleOpt,
    groups: []const LangGroup,
    trs_empty: bool,

    // Edit-message mode.
    em_action: []const u8,
    em_role: []const u8,
    em_content: []const u8,
    err_em_role: []const u8,
    err_em_content: []const u8,
};

pub const Input = struct {
    state: State,
    /// Null on the home page (no conversation open).
    conv: ?types.Conversation = null,
    messages: []const types.Message = &.{},
    translations: []const types.Translation = &.{},
    cards: []const types.Conversation = &.{},
    /// Re-rendered forms (validation errors and echoed input).
    conv_form: ?forms.ConversationForm = null,
    composer: ?forms.MessageForm = null,
    edit_msg: ?forms.MessageForm = null,
    tr: ?forms.TranslationForm = null,
    /// Short confirmation shown in the work pane ("Added").
    notice: []const u8 = "",
};

pub fn shell(a: std.mem.Allocator, in: Input) !Shell {
    const conv_id: i32 = if (in.conv) |c| c.id else 0;
    const route = try route_mod.resolve(a, in.messages, .{ .via = in.state.via, .sel = in.state.sel, .leaf = in.state.leaf });
    const sel = route.sel;
    const leaf = route.leaf;
    const lang = effectiveLang(in.translations, in.state.lang);
    const source: []const u8 = if (in.conv) |c| c.source_language else validate.default_language;

    // Replies below each message, for the delete confirmation (parents precede children).
    const replies = try a.alloc(usize, in.messages.len);
    @memset(replies, 0);
    var i = in.messages.len;
    while (i > 0) {
        i -= 1;
        const pid = in.messages[i].parent_message_id orelse continue;
        for (in.messages[0..i], 0..) |p, pi| {
            if (p.id == pid) {
                replies[pi] += replies[i] + 1;
                break;
            }
        }
    }

    const bubbles = try a.alloc(Bubble, route.steps.len);
    for (route.steps, bubbles) |s, *b| {
        const m = in.messages[s.index];
        var n: usize = 0;
        for (in.translations) |t| {
            if (t.message_id == m.id) n += 1;
        }
        const selected = sel != null and sel.? == m.id;
        // In a translated view show the newest translation in that language, else the marked source text.
        const pick: Pick = if (lang.len > 0) pickTranslation(in.translations, m.id, lang) else .{};
        const missing = lang.len > 0 and pick.tr == null;
        const shown_n = if (lang.len > 0) pick.count else n;
        const sibs = try a.alloc(SibOpt, if (s.count > 1) s.siblings.len else 0);
        for (sibs, 0..) |*o, k| {
            const sm = in.messages[s.siblings[k]];
            const here = sm.id == m.id;
            o.* = .{
                .label = try std.fmt.allocPrint(a, "{d}. {s}: {s}", .{ k + 1, sm.role, try snippet(a, sm.content, 40) }),
                .url = try viaUrl(a, conv_id, sm.id, sel, lang),
                .cls = if (here) "sib here" else "sib",
                .current = if (here) "true" else "false",
            };
        }
        b.* = .{
            .id = m.id,
            .role = m.role,
            .content = if (pick.tr) |t| t.content else m.content,
            .cls = if (selected and missing) "bubble sel untranslated" else if (selected) "bubble sel" else if (missing) "bubble untranslated" else "bubble",
            .role_cls = roleClass(in.messages, m.role),
            .selected = selected,
            .current = if (selected) "true" else "false",
            .select_url = try url(a, conv_id, m.id, leaf, .none, lang),
            .edit_url = try url(a, conv_id, m.id, leaf, .message, lang),
            .delete_url = try std.fmt.allocPrint(a, "/ui/message/{d}{s}", .{ m.id, try stateQuery(a, null, leaf, lang) }),
            .delete_confirm = switch (replies[s.index]) {
                0 => "Delete this message?",
                1 => "Delete this message and its 1 reply?",
                else => try std.fmt.allocPrint(a, "Delete this message and its {d} replies?", .{replies[s.index]}),
            },
            .fork = s.count > 1,
            .fork_label = try std.fmt.allocPrint(a, "Branch {d} of {d}", .{ s.pos, s.count }),
            .prev_url = if (s.prev) |p| try viaUrl(a, conv_id, p, sel, lang) else "",
            .next_url = if (s.next) |nx| try viaUrl(a, conv_id, nx, sel, lang) else "",
            .prev_attr = if (s.prev == null) "disabled" else "",
            .next_attr = if (s.next == null) "disabled" else "",
            .sibs = sibs,
            .badge = if (shown_n == 0) "" else try std.fmt.allocPrint(a, "{d}", .{shown_n}),
            .badge_title = switch (n) {
                0 => "",
                1 => "1 translation",
                else => try std.fmt.allocPrint(a, "{d} translations", .{n}),
            },
            .text_lang = if (pick.tr != null) lang else source,
            .src_tag = if (missing) "source" else "",
            .more = if (pick.count > 1) try std.fmt.allocPrint(a, "+{d}", .{pick.count - 1}) else "",
            .title = if (missing)
                try std.fmt.allocPrint(a, "No {s} translation yet", .{lang})
            else if (pick.count > 1)
                try std.fmt.allocPrint(a, "{d} translations in {s}; see the panel", .{ pick.count, lang })
            else
                "",
        };
    }

    var leaf_msg: ?types.Message = null;
    var sel_msg: ?types.Message = null;
    for (in.messages) |m| {
        if (leaf != null and m.id == leaf.?) leaf_msg = m;
        if (sel != null and m.id == sel.?) sel_msg = m;
    }
    const target = sel_msg orelse leaf_msg;

    // Translations of the selected message, grouped by language in first-use order; the most recent
    // translation in the conversation seeds the language.
    var latest: ?types.Translation = null;
    var editing: ?types.Translation = null;
    var groups: std.ArrayList(LangGroup) = .empty;
    var group_rows: std.ArrayList(std.ArrayList(TrRow)) = .empty;
    var trs_total: usize = 0;
    for (in.translations) |t| {
        latest = t; // ascending id
        const sm = sel_msg orelse continue;
        if (t.message_id != sm.id) continue;
        const edit_here = in.state.edit == .translation and in.state.edit.translation == t.id;
        if (edit_here) editing = t;
        const row: TrRow = .{
            .id = t.id,
            .language = t.language,
            .content = t.content,
            .cls = if (edit_here) "editing" else "",
            .edit_url = try url(a, conv_id, sm.id, leaf, .{ .translation = t.id }, lang),
            .delete_url = try std.fmt.allocPrint(a, "/ui/translation/{d}{s}", .{ t.id, try stateQuery(a, sm.id, leaf, lang) }),
        };
        trs_total += 1;
        var found = false;
        for (groups.items, 0..) |g, gi| {
            if (std.mem.eql(u8, g.code, t.language)) {
                try group_rows.items[gi].append(a, row);
                found = true;
                break;
            }
        }
        if (!found) {
            try groups.append(a, .{ .code = t.language, .count = "", .rows = &.{} });
            var rows: std.ArrayList(TrRow) = .empty;
            try rows.append(a, row);
            try group_rows.append(a, rows);
        }
    }
    for (groups.items, group_rows.items) |*g, rows| {
        g.rows = rows.items;
        g.count = try std.fmt.allocPrint(a, "{d}", .{rows.items.len});
    }

    const edit_msg_mode = sel_msg != null and in.state.edit == .message;
    const translate_mode = sel_msg != null and !edit_msg_mode;
    const sm_id: i32 = if (sel_msg) |m| m.id else 0;
    const q_sel = try stateQuery(a, sel, leaf, lang);
    const lang_opts = try languageOptions(a, in.translations, source, lang);

    const tr_in = in.tr orelse forms.TranslationForm{
        .language = if (editing) |e| e.language else if (lang.len > 0) lang else if (latest) |l| l.language else "",
        .content = if (editing) |e| e.content else "",
    };
    const em_in = in.edit_msg orelse forms.MessageForm{
        .role = if (sel_msg) |m| m.role else "",
        .content = if (sel_msg) |m| m.content else "",
    };
    const composer = in.composer orelse forms.MessageForm{ .role = defaultRole(in.messages, if (target) |t| t.role else null) };

    // The open conversation first, so it is never lost in the grid.
    const cards = try a.alloc(Card, in.cards.len);
    var at: usize = 0;
    for ([_]bool{ true, false }) |open_pass| {
        for (in.cards) |c| {
            if ((c.id == conv_id) != open_pass) continue;
            cards[at] = .{
                .id = c.id,
                .title = c.title,
                .description = c.description,
                .language = c.source_language,
                .cls = if (c.id == conv_id) "card sel" else "card",
                .open_url = try std.fmt.allocPrint(a, "/ui/conversation/{d}", .{c.id}),
                .delete_url = try std.fmt.allocPrint(a, "/ui/conversation/{d}{s}", .{ c.id, try curQuery(a, conv_id, sel, leaf, lang) }),
            };
            at += 1;
        }
    }

    return .{
        .pane = if (in.conv == null or sel_msg != null) "work" else "chat",

        .has_conv = in.conv != null,
        .chat_lang = if (lang.len > 0) lang else source,
        .source_code = source,
        .has_toggle = lang_opts.len > 1,
        .lang_opts = lang_opts,
        .toggle_url = try url(a, conv_id, sel, leaf, .none, ""),
        .composer_lang = lang,
        .conv_title = if (in.conv) |c| c.title else "",
        .bubbles = bubbles,
        .empty_chat = bubbles.len == 0,
        .empty_text = if (in.conv != null) "No messages yet. Write the first one below." else "Open a conversation to start.",
        .composer_action = if (in.conv != null) try std.fmt.allocPrint(a, "/ui/conversation/{d}/messages", .{conv_id}) else "",
        .composer_sel = if (sel) |s| try std.fmt.allocPrint(a, "{d}", .{s}) else "",
        .composer_leaf = if (leaf) |l| try std.fmt.allocPrint(a, "{d}", .{l}) else "",
        .composer_role = composer.role,
        .composer_err = if (composer.err_content.len > 0) composer.err_content else composer.err_role,
        .composer_hidden = if (in.conv != null) "" else "hidden",
        .roles = try roleSuggestions(a, in.messages),
        .chip = sel_msg != null,
        .chip_label = if (sel != null and leaf != null and sel.? != leaf.?) "Branching from" else "Replying to",
        .chip_text = if (sel_msg) |m| try snippet(a, m.content, snippet_len) else "",
        .chip_clear_url = try url(a, conv_id, null, leaf, .none, lang),

        .mode_cards = sel_msg == null,
        .mode_translate = translate_mode,
        .mode_edit_msg = edit_msg_mode,

        .q = in.state.q,
        .search_url = if (in.conv != null) try url(a, conv_id, null, leaf, .none, lang) else "/",
        .cards = cards,
        .cards_empty = cards.len == 0,
        .form = in.conv_form orelse .{ .language = validate.default_language },
        .new_open = if (in.conv_form != null) "open" else "",

        .back_url = if (in.conv != null) try url(a, conv_id, null, leaf, .none, lang) else "/",
        .cancel_url = try url(a, conv_id, sel, leaf, .none, lang),
        .sel_role = if (sel_msg) |m| m.role else "",
        .sel_content = if (sel_msg) |m| m.content else "",
        .sel_role_cls = if (sel_msg) |m| roleClass(in.messages, m.role) else "r0",
        .tr_edit = editing != null,
        .tr_action = if (editing) |e|
            try std.fmt.allocPrint(a, "/ui/translation/{d}{s}", .{ e.id, q_sel })
        else
            try std.fmt.allocPrint(a, "/ui/message/{d}/translations{s}", .{ sm_id, q_sel }),
        .tr_heading = if (editing != null) "Editing translation" else "Add a translation",
        .tr_button = if (editing != null) "Save" else "Translate",
        .tr_language = tr_in.language,
        .tr_content = tr_in.content,
        .err_tr_language = tr_in.err_language,
        .err_tr_content = tr_in.err_content,
        .notice = in.notice,
        .langs = try languageSuggestions(a, in.translations, if (in.conv) |c| c.source_language else ""),
        .groups = groups.items,
        .trs_empty = trs_total == 0,

        .em_action = try std.fmt.allocPrint(a, "/ui/message/{d}{s}", .{ sm_id, try stateQuery(a, null, leaf, lang) }),
        .em_role = em_in.role,
        .em_content = em_in.content,
        .err_em_role = em_in.err_role,
        .err_em_content = em_in.err_content,
    };
}

/// `?cur=<open conversation>&sel=..&leaf=..` so deleting another card keeps the open one.
fn curQuery(a: std.mem.Allocator, conv: i32, sel: ?i32, leaf: ?i32, lang: []const u8) ![]const u8 {
    if (conv == 0) return "";
    var aw: std.Io.Writer.Allocating = .init(a);
    try aw.writer.print("?cur={d}", .{conv});
    if (sel) |v| try aw.writer.print("&sel={d}", .{v});
    if (leaf) |v| try aw.writer.print("&leaf={d}", .{v});
    var sep: u8 = '&';
    try langParam(&aw.writer, &sep, lang);
    return aw.written();
}

const std = @import("std");
const contract = @import("contract");
const types = @import("../types/root.zig");
const validate = types.validate;
const forms = @import("forms.zig");
const route_mod = @import("route.zig");

fn msg(id: i32, parent: ?i32, role: []const u8) types.Message {
    return .{ .id = id, .conversation_id = 1, .parent_message_id = parent, .role = role, .content = "c", .created_at = 0, .updated_at = 0 };
}

test "roleSuggestions: most recent first, deduplicated, person last when unused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ms = [_]types.Message{ msg(1, null, "waiter"), msg(2, 1, "guest"), msg(3, 2, "waiter") };
    const got = try roleSuggestions(a, &ms);
    try std.testing.expectEqual(@as(usize, 3), got.len);
    try std.testing.expectEqualStrings("waiter", got[0].name);
    try std.testing.expectEqualStrings("guest", got[1].name);
    try std.testing.expectEqualStrings("person", got[2].name);

    const used = try roleSuggestions(a, &[_]types.Message{ msg(1, null, "person"), msg(2, 1, "guest") });
    try std.testing.expectEqualStrings("guest", used[0].name);
    try std.testing.expectEqual(@as(usize, 2), used.len);
    try std.testing.expectEqualStrings("person", (try roleSuggestions(a, &.{}))[0].name);
}

test "urls and edit parsing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("/ui/conversation/3", try url(a, 3, null, null, .none, ""));
    try std.testing.expectEqualStrings("/ui/conversation/3?sel=4&leaf=9&edit=t5", try url(a, 3, 4, 9, .{ .translation = 5 }, ""));
    try std.testing.expectEqualStrings("/ui/conversation/3?leaf=9&edit=m", try url(a, 3, null, 9, .message, ""));
    try std.testing.expectEqualStrings("?leaf=9", try stateQuery(a, null, 9, ""));
    try std.testing.expectEqualStrings("/ui/conversation/3?sel=4&leaf=9&edit=m&lang=es", try url(a, 3, 4, 9, .message, "es"));
    try std.testing.expectEqualStrings("/ui/conversation/3?via=7&sel=4&lang=es", try viaUrl(a, 3, 7, 4, "es"));
    try std.testing.expectEqualStrings("/ui/conversation/3?via=7", try viaUrl(a, 3, 7, null, ""));
    try std.testing.expectEqualStrings("?leaf=9&lang=es", try stateQuery(a, null, 9, "es"));
    try std.testing.expectEqualStrings("?lang=es", try stateQuery(a, null, null, "es"));
    try std.testing.expectEqual(Edit.message, parseEdit("m"));
    try std.testing.expectEqual(@as(i32, 12), parseEdit("t12").translation);
    try std.testing.expectEqual(Edit.none, parseEdit("t0"));
    try std.testing.expectEqual(Edit.none, parseEdit("x"));
}

test "defaultRole: the other speaker when exactly two roles exist" {
    const two = [_]types.Message{ msg(1, null, "a"), msg(2, 1, "b"), msg(3, 2, "a") };
    try std.testing.expectEqualStrings("b", defaultRole(&two, "a"));
    try std.testing.expectEqualStrings("a", defaultRole(&two, "b"));
    const three = [_]types.Message{ msg(1, null, "a"), msg(2, 1, "b"), msg(3, 2, "c") };
    try std.testing.expectEqualStrings("b", defaultRole(&three, "b"));
    try std.testing.expectEqualStrings("a", defaultRole(&.{msg(1, null, "a")}, "a"));
    try std.testing.expectEqualStrings("person", defaultRole(&.{}, null));
}

test "languageSuggestions: used, source, then common, deduplicated" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const trs = [_]types.Translation{
        .{ .id = 1, .message_id = 1, .language = "fr", .content = "x", .created_at = 0, .updated_at = 0 },
        .{ .id = 2, .message_id = 1, .language = "fr", .content = "y", .created_at = 0, .updated_at = 0 },
    };
    const got = try languageSuggestions(arena.allocator(), &trs, "pt-BR");
    try std.testing.expectEqualStrings("fr", got[0].name);
    try std.testing.expectEqualStrings("pt-BR", got[1].name);
    try std.testing.expectEqualStrings("en", got[2].name);
    for (got[3..]) |g| try std.testing.expect(!std.mem.eql(u8, g.name, "fr"));
}

test "shell: route bubbles, fork bar, modes, language seed, grouping" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const conv: types.Conversation = .{ .id = 1, .title = "T", .description = "", .source_language = "en", .created_at = 0, .updated_at = 0 };
    const ms = [_]types.Message{ msg(1, null, "a"), msg(2, 1, "b"), msg(3, 1, "b"), msg(4, 2, "a") };
    const trs = [_]types.Translation{
        .{ .id = 1, .message_id = 1, .language = "es", .content = "x", .created_at = 0, .updated_at = 0 },
        .{ .id = 2, .message_id = 1, .language = "fr", .content = "y", .created_at = 0, .updated_at = 0 },
        .{ .id = 3, .message_id = 1, .language = "es", .content = "z", .created_at = 0, .updated_at = 0 },
    };

    const cards = try shell(a, .{ .state = .{}, .conv = conv, .messages = &ms, .translations = &trs, .cards = &.{ .{ .id = 9, .title = "o", .description = "", .source_language = "en", .created_at = 0, .updated_at = 0 }, conv } });
    try std.testing.expect(cards.mode_cards and !cards.mode_translate);
    try std.testing.expectEqualStrings("chat", cards.pane);
    try std.testing.expectEqual(@as(usize, 3), cards.bubbles.len); // 1, 2, 4
    try std.testing.expect(!cards.bubbles[0].fork and cards.bubbles[1].fork);
    try std.testing.expectEqualStrings("Branch 1 of 2", cards.bubbles[1].fork_label);
    try std.testing.expectEqual(@as(usize, 2), cards.bubbles[1].sibs.len);
    try std.testing.expectEqualStrings("disabled", cards.bubbles[1].prev_attr);
    try std.testing.expectEqualStrings("/ui/conversation/1?via=3", cards.bubbles[1].next_url);
    try std.testing.expectEqualStrings("3", cards.bubbles[0].badge);
    try std.testing.expectEqualStrings("Delete this message and its 3 replies?", cards.bubbles[0].delete_confirm);
    try std.testing.expectEqualStrings("b", cards.composer_role); // the other of exactly two roles
    try std.testing.expectEqualStrings("card sel", cards.cards[0].cls); // open conversation first
    try std.testing.expectEqualStrings("/ui/conversation/9?cur=1&leaf=4", cards.cards[1].delete_url);

    // Switching branch keeps a selection that is still on the new route, and the mode.
    const sw = try shell(a, .{ .state = .{ .via = 3, .sel = 1 }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expect(sw.mode_translate and sw.chip);
    try std.testing.expectEqual(@as(i32, 3), sw.bubbles[1].id);

    const picked = try shell(a, .{ .state = .{ .sel = 1, .leaf = 4 }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expect(picked.mode_translate and picked.chip);
    try std.testing.expectEqualStrings("work", picked.pane);
    try std.testing.expectEqualStrings("Branching from", picked.chip_label);
    try std.testing.expectEqualStrings("bubble sel", picked.bubbles[0].cls);
    try std.testing.expectEqualStrings("es", picked.tr_language); // latest translation in the conversation
    try std.testing.expectEqual(@as(usize, 2), picked.groups.len);
    try std.testing.expectEqualStrings("2", picked.groups[0].count);
    try std.testing.expectEqualStrings("1", picked.composer_sel);
    try std.testing.expectEqualStrings("4", picked.composer_leaf);

    const editing = try shell(a, .{ .state = .{ .sel = 1, .edit = .{ .translation = 3 } }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expect(editing.tr_edit);
    try std.testing.expectEqualStrings("editing", editing.groups[0].rows[1].cls);
    try std.testing.expectEqualStrings("Save", editing.tr_button);
    const em = try shell(a, .{ .state = .{ .sel = 2, .edit = .message }, .conv = conv, .messages = &ms });
    try std.testing.expect(em.mode_edit_msg and !em.mode_translate);

    const none = try shell(a, .{ .state = .{} });
    try std.testing.expectEqualStrings("hidden", none.composer_hidden);
    try std.testing.expect(none.empty_chat and none.mode_cards);
}

fn tr(id: i32, message_id: i32, language: []const u8, content: []const u8, updated: i64) types.Translation {
    return .{ .id = id, .message_id = message_id, .language = language, .content = content, .created_at = 0, .updated_at = updated };
}

test "pickTranslation: newest by updated_at then id; effectiveLang and languageOptions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const trs = [_]types.Translation{
        tr(1, 1, "es", "old", 5),
        tr(2, 1, "fr", "fr1", 1),
        tr(3, 1, "es", "new", 9),
        tr(4, 1, "es", "tie-high", 9),
        tr(5, 2, "fr", "other", 1),
    };
    const p = pickTranslation(&trs, 1, "es");
    try std.testing.expectEqualStrings("tie-high", p.tr.?.content); // same updated_at: the higher id wins
    try std.testing.expectEqual(@as(usize, 3), p.count);
    try std.testing.expect(pickTranslation(&trs, 2, "es").tr == null);

    try std.testing.expectEqualStrings("es", effectiveLang(&trs, "ES"));
    try std.testing.expectEqualStrings("", effectiveLang(&trs, "de")); // unused
    try std.testing.expectEqualStrings("", effectiveLang(&trs, ""));

    const opts = try languageOptions(a, &trs, "en", "fr");
    try std.testing.expectEqual(@as(usize, 3), opts.len);
    try std.testing.expectEqualStrings("Source (en)", opts[0].label);
    try std.testing.expectEqualStrings("es", opts[1].code);
    try std.testing.expectEqualStrings("checked", opts[2].checked);
    try std.testing.expectEqualStrings("", opts[0].checked);
}

test "shell in a translated language: picks, fallback marking, +N, threads lang" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const conv: types.Conversation = .{ .id = 1, .title = "T", .description = "", .source_language = "en", .created_at = 0, .updated_at = 0 };
    const ms = [_]types.Message{ msg(1, null, "a"), msg(2, 1, "b"), msg(3, 1, "b") };
    const trs = [_]types.Translation{ tr(1, 1, "es", "uno", 1), tr(2, 1, "es", "uno bis", 2), tr(3, 3, "fr", "trois", 1) };

    const es = try shell(a, .{ .state = .{ .lang = "es" }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expectEqualStrings("uno bis", es.bubbles[0].content);
    try std.testing.expectEqualStrings("+1", es.bubbles[0].more);
    try std.testing.expectEqualStrings("2 translations in es; see the panel", es.bubbles[0].title);
    try std.testing.expectEqualStrings("2", es.bubbles[0].badge);
    try std.testing.expectEqualStrings("es", es.bubbles[0].text_lang);
    try std.testing.expectEqualStrings("bubble untranslated", es.bubbles[1].cls);
    try std.testing.expectEqualStrings("source", es.bubbles[1].src_tag);
    try std.testing.expectEqualStrings("No es translation yet", es.bubbles[1].title);
    try std.testing.expectEqualStrings("en", es.bubbles[1].text_lang);
    try std.testing.expectEqualStrings("/ui/conversation/1?via=3&lang=es", es.bubbles[1].next_url);
    try std.testing.expectEqualStrings("/ui/conversation/1?sel=2&leaf=2&lang=es", es.bubbles[1].select_url);
    try std.testing.expectEqualStrings("es", es.composer_lang);
    try std.testing.expectEqualStrings("es", es.chat_lang);
    try std.testing.expect(es.has_toggle);

    const none = try shell(a, .{ .state = .{ .lang = "xx" }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expectEqualStrings("", none.composer_lang);
    try std.testing.expectEqualStrings("en", none.chat_lang);
    try std.testing.expectEqualStrings("bubble", none.bubbles[1].cls);

    const picked = try shell(a, .{ .state = .{ .sel = 1, .lang = "fr" }, .conv = conv, .messages = &ms, .translations = &trs });
    try std.testing.expectEqualStrings("fr", picked.tr_language); // prefilled with the active language

    try std.testing.expect(!(try shell(a, .{ .state = .{}, .conv = conv, .messages = &ms })).has_toggle);
}
