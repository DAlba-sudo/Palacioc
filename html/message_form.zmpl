@if ($.form.is_edit)
<form class="form" hx-put="/ui/message/{{$.form.id}}" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false" hx-disabled-elt="find button[type=submit]">
@else
<form class="form" hx-post="/ui/message" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false" hx-disabled-elt="find button[type=submit]">
<input type="hidden" name="conversation_id" value="{{$.form.conversation_id}}">
<input type="hidden" name="parent_message_id" value="{{$.form.parent_id}}">
@end
<h2>Message</h2>
<p class="muted">{{$.form.hint}}</p>
<div class="field">
<label for="msg-role">Role</label>
<input id="msg-role" name="role" type="text" placeholder="person" value="{{$.form.role}}">
@if ($.form.err_role)
<p class="field-error">{{$.form.err_role}}</p>
@end
</div>
<div class="field">
<label for="msg-content">Content</label>
<textarea id="msg-content" name="content" rows="4" autofocus>{{$.form.content}}</textarea>
@if ($.form.err_content)
<p class="field-error">{{$.form.err_content}}</p>
@end
</div>
<div class="actions">
<button type="button" hx-get="/ui/panel/close" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Cancel</button>
<button type="submit">Save</button>
</div>
</form>
