<div id="shell" class="shell" data-pane="{{$.pane}}" hx-target="#work" hx-select="#work" hx-select-oob="#chat-log,#composer-meta" hx-swap="outerHTML" hx-push-url="false">
<nav class="tabs" aria-label="Panes">
<button type="button" data-pane="chat" aria-pressed="true">Chat</button>
<button type="button" data-pane="work" aria-pressed="false">Work</button>
</nav>
<section class="chat" aria-label="Chat">
<header class="chat-head">
@if ($.has_conv)
<a class="back" href="/" hx-get="/" hx-target="#shell" hx-select="#shell" hx-select-oob="unset" hx-push-url="true">&larr; All</a>
<h1>{{$.conv_title}}</h1>
@else
<h1>Palacioc</h1>
@end
</header>
<div id="chat-log" class="chat-log" aria-live="polite">
@if ($.empty_chat)
<p class="empty">{{$.empty_text}}</p>
@end
@for ($.bubbles) |b| {
@zig {
  const sibs = b.get("sibs").?;
  const fork = try b.chainRefT(bool, "fork");
  const selected = try b.chainRefT(bool, "selected");
}
@if (fork)
<div class="fork" role="group" aria-label="{{b.fork_label}}">
<button type="button" class="fork-nav" aria-label="Previous branch" {{b.prev_attr}} hx-get="{{b.prev_url}}" hx-push-url="true">&lsaquo;</button>
<details>
<summary>{{b.fork_label}}</summary>
<ul class="sibs">
@for (sibs) |s| {
<li><button type="button" class="{{s.cls}}" aria-current="{{s.current}}" hx-get="{{s.url}}" hx-push-url="true">{{s.label}}</button></li>
}
</ul>
</details>
<button type="button" class="fork-nav" aria-label="Next branch" {{b.next_attr}} hx-get="{{b.next_url}}" hx-push-url="true">&rsaquo;</button>
</div>
@end
<div class="msg {{b.role_cls}}">
<button type="button" class="{{b.cls}}" aria-current="{{b.current}}" data-pane="work" hx-get="{{b.select_url}}" hx-push-url="true">{{b.content}}</button>
<div class="msg-meta">
<span class="author">{{b.role}}</span>
<span class="badge" title="{{b.badge_title}}">{{b.badge}}</span>
<span class="msg-actions">
@if (selected)
<button type="button" class="btn-sm" data-pane="chat" data-focus="compose-text" hx-get="{{b.select_url}}" hx-push-url="true">Branch from here</button>
@end
<button type="button" class="btn-sm" data-pane="work" hx-get="{{b.edit_url}}">Edit</button>
<button type="button" class="btn-sm danger" hx-delete="{{b.delete_url}}" hx-confirm="{{b.delete_confirm}}">Delete</button>
</span>
</div>
</div>
}
</div>
<form id="composer" class="composer" hx-post="{{$.composer_action}}" {{$.composer_hidden}}>
<div id="composer-meta" class="composer-meta">
<input type="hidden" name="sel" value="{{$.composer_sel}}">
<input type="hidden" name="leaf" value="{{$.composer_leaf}}">
@if ($.chip)
<span class="chip">{{$.chip_label}}: {{$.chip_text}} <button type="button" class="link" aria-label="Reply to the end of the route instead" hx-get="{{$.chip_clear_url}}" hx-push-url="true">&times;</button></span>
@end
<label class="role-field">Role <input name="role" list="roles" value="{{$.composer_role}}" maxlength="64" autocomplete="off"></label>
<datalist id="roles">
@for ($.roles) |r| {
<option value="{{r.name}}"></option>
}
</datalist>
<p class="field-error" role="alert">{{$.composer_err}}</p>
</div>
<textarea id="compose-text" name="content" rows="3" aria-label="New message" placeholder="Press &quot;Enter&quot; to create a new message in the conversation..."></textarea>
</form>
</section>
<section id="work" class="work" aria-live="polite">
@if ($.mode_cards)
<h1>Conversations</h1>
<div class="search">
<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><circle cx="10" cy="10" r="6.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M15 15l6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
<input type="search" name="q" value="{{$.q}}" placeholder="Search" aria-label="Search conversations" hx-get="{{$.search_url}}" hx-trigger="input changed delay:300ms, search" hx-target="#cards" hx-select="#cards" hx-select-oob="unset">
</div>
<details id="new-conv" class="new-conv" {{$.new_open}}>
<summary class="primary">+ New conversation</summary>
<form class="form" hx-post="/ui/conversations" hx-target="#new-conv" hx-select="#new-conv" hx-select-oob="unset" hx-disabled-elt="find button[type=submit]">
<div class="field">
<label for="conv-title">Title</label>
<input id="conv-title" name="title" type="text" value="{{$.form.title}}">
<p class="field-error">{{$.form.err_title}}</p>
</div>
<div class="field">
<label for="conv-description">Description</label>
<input id="conv-description" name="description" type="text" value="{{$.form.description}}">
<p class="field-error">{{$.form.err_description}}</p>
</div>
<div class="field">
<label for="conv-language">Language you write in</label>
<input id="conv-language" name="source_language" type="text" value="{{$.form.language}}">
<p class="field-error">{{$.form.err_language}}</p>
</div>
<div class="field">
<label for="conv-first">First message (optional)</label>
<textarea id="conv-first" name="initial_message" rows="2">{{$.form.first_message}}</textarea>
<p class="field-error">{{$.form.err_first_message}}</p>
</div>
<button type="submit" class="primary">Create</button>
</form>
</details>
<div id="cards" class="cards">
@if ($.cards_empty)
<p class="muted">No conversations found.</p>
@end
@for ($.cards) |c| {
<div class="{{c.cls}}">
<a class="open" href="{{c.open_url}}" hx-get="{{c.open_url}}" hx-target="#shell" hx-select="#shell" hx-select-oob="unset" hx-push-url="true"><h2>{{c.title}}</h2></a>
<span class="lang">{{c.language}}</span>
<p class="desc">{{c.description}}</p>
<button type="button" class="del" hx-delete="{{c.delete_url}}" hx-confirm="Delete this conversation and all its messages?" hx-include=".search input" hx-target="#cards" hx-select="#cards" hx-select-oob="unset">Delete</button>
</div>
}
</div>
@end
@if ($.mode_translate)
<p><button type="button" class="back" hx-get="{{$.back_url}}" hx-push-url="true">&larr; Conversations</button></p>
<div class="source msg {{$.sel_role_cls}}">
<div class="bubble">{{$.sel_content}}</div>
<div class="msg-meta"><span class="author">{{$.sel_role}}</span></div>
</div>
@if ($.tr_edit)
<form class="tr-form editing" hx-put="{{$.tr_action}}">
<h2 class="edit-head">{{$.tr_heading}}</h2>
@else
<form class="tr-form" hx-post="{{$.tr_action}}">
<h2 class="sr">{{$.tr_heading}}</h2>
@end
<label class="sr" for="tr-content">Translation</label>
<textarea id="tr-content" name="content" rows="3" placeholder="Enter a new translation here...">{{$.tr_content}}</textarea>
<p class="field-error">{{$.err_tr_content}}</p>
<div class="tr-row">
<label class="sr" for="tr-language">Language</label>
<input id="tr-language" name="language" type="text" list="langs" placeholder="Language" value="{{$.tr_language}}" autocomplete="off">
<datalist id="langs">
@for ($.langs) |l| {
<option value="{{l.name}}"></option>
}
</datalist>
<button type="submit" class="primary">{{$.tr_button}}</button>
@if ($.tr_edit)
<button type="button" class="secondary" hx-get="{{$.cancel_url}}">Cancel</button>
@end
</div>
<p class="field-error">{{$.err_tr_language}}</p>
<p class="notice" role="status">{{$.notice}}</p>
</form>
<h2>Alternative Translations</h2>
<div class="alts">
@if ($.trs_empty)
<p class="muted pad">No translations yet.</p>
@end
@for ($.groups) |g| {
@zig {
  const rows = g.get("rows").?;
}
<h3 class="lang-head"><span class="lang">{{g.code}}</span> <span class="count">{{g.count}}</span></h3>
<ul class="rows">
@for (rows) |t| {
<li class="{{t.cls}}"><span class="txt">{{t.content}}</span>
<span class="row-actions"><button type="button" class="btn-sm" hx-get="{{t.edit_url}}">Edit</button>
<button type="button" class="btn-sm danger" hx-delete="{{t.delete_url}}" hx-confirm="Delete this translation?">Delete</button></span></li>
}
</ul>
}
</div>
@end
@if ($.mode_edit_msg)
<p><button type="button" class="back" hx-get="{{$.cancel_url}}" hx-push-url="true">&larr; Back</button></p>
<form class="tr-form" hx-put="{{$.em_action}}">
<h2>Edit message</h2>
<label for="em-role">Role</label>
<input id="em-role" name="role" type="text" list="roles" maxlength="64" value="{{$.em_role}}" autocomplete="off">
<p class="field-error">{{$.err_em_role}}</p>
<label for="em-content">Content</label>
<textarea id="em-content" name="content" rows="4">{{$.em_content}}</textarea>
<p class="field-error">{{$.err_em_content}}</p>
<div class="tr-row"><button type="submit" class="primary">Save</button><button type="button" class="secondary" hx-get="{{$.cancel_url}}">Cancel</button></div>
</form>
@end
</section>
</div>
