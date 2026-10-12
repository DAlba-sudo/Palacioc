@if ($.form.is_edit)
<form class="form" hx-put="/ui/translation/{{$.form.id}}" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false" hx-disabled-elt="find button[type=submit]">
@else
<form class="form" hx-post="/ui/translation" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false" hx-disabled-elt="find button[type=submit]">
<input type="hidden" name="message_id" value="{{$.form.message_id}}">
@end
<h2>Translation</h2>
<p class="muted">{{$.form.source}}</p>
<div class="field">
<label for="tr-language">Language</label>
<input id="tr-language" name="language" type="text" placeholder="es" value="{{$.form.language}}">
@if ($.form.err_language)
<p class="field-error">{{$.form.err_language}}</p>
@end
</div>
<div class="field">
<label for="tr-content">Translation</label>
<textarea id="tr-content" name="content" rows="4" autofocus>{{$.form.content}}</textarea>
@if ($.form.err_content)
<p class="field-error">{{$.form.err_content}}</p>
@end
</div>
<div class="actions">
<button type="button" hx-get="/ui/message/{{$.form.message_id}}/menu" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Cancel</button>
<button type="submit">Save</button>
</div>
</form>
