//! Server-rendered HTMX UI (templates in html/).
pub const forms = @import("forms.zig");
pub const handlers = @import("handlers.zig");
pub const render = @import("render.zig");
pub const static = @import("static.zig");
pub const view = @import("view.zig");

test {
    _ = forms;
    _ = render;
    _ = view;
    _ = @import("templates_test.zig");
}
