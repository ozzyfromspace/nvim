; Extend nvim-treesitter's TypeScript injections. Files under
; after/queries/<lang>/<name>.scm are APPENDED to the bundled queries,
; so we don't have to copy the upstream file — just add our rules.
;
; Inject HTML highlighting into tagged template literals whose tag is
; one of `html`, `svg`, or `vue`. Vue template fragments aren't true
; SFCs, so the HTML parser is the best fit — it covers attributes,
; directives (v-bind, @click, :class), and self-closing tags. Vue's
; {{ interpolation }} renders as plain text, which is an acceptable
; gap until someone writes a dedicated grammar.

((call_expression
  function: (identifier) @_tag
  arguments: (template_string) @injection.content)
  (#any-of? @_tag "html" "svg" "vue")
  (#set! injection.language "html")
  (#offset! @injection.content 0 1 0 -1))
