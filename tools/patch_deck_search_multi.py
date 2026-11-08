import pathlib

p = pathlib.Path('scripts/deck_search.gd')
s = p.read_text(encoding='utf-8')

# 1) signal
s = s.replace('signal finished(chosen_id: int)\n', 'signal finished(chosen_id: int)\nsignal finished_multi(chosen_ids: Array)\n', 1)

# 2) state
old = '''var _selected_node: Control = null
'''
new = '''var _selected_node: Control = null
## Multi-select state. `_selected_ids` is paging-safe and can contain the same id more than once, because a deck
## may hold duplicate copies and a total-cost rule allows both. `_node_selected` says which visible copy is orange.
var _multi: bool = false
var _selection = null
var _selected_ids: Array = []
var _node_selected: Dictionary = {}
'''
assert old in s
s = s.replace(old, new, 1)

# 3) confirm callback
s = s.replace('_confirm.pressed.connect(func(): _finish(selected_id))', '_confirm.pressed.connect(_confirm_pressed)', 1)

# 4) reset multi state when opening a single-select view/window
old = '''func open_view(ids: Array, title: String) -> void:
\tvar shown: Array = []'''
new = '''func open_view(ids: Array, title: String) -> void:
\t_multi = false
\t_selection = null
\t_selected_ids.clear()
\tvar shown: Array = []'''
assert old in s
s = s.replace(old, new, 1)

old = '''func open(deck_ids: Array, filter: Dictionary, subtitle_text: String = "") -> void:
\tvar matching: Array = []'''
new = '''func open(deck_ids: Array, filter: Dictionary, subtitle_text: String = "") -> void:
\t_multi = false
\t_selection = null
\t_selected_ids.clear()
\tvar matching: Array = []'''
assert old in s
s = s.replace(old, new, 1)

# 5) Add open_multi before _rebuild_page
anchor = '''## Rebuilds the fan for the current page. Called on open and whenever the page changes.
func _rebuild_page() -> void:'''
multi_open = '''## Opens the window in MULTI-SELECT mode. `request` is a SelectionRequest: its constraints decide which cards
## remain selectable as the selection changes (`request.allows`) and whether Confirm is legal (`request.valid`).
## The filter is passed separately so the same window can be used before the constraint object exists.
func open_multi(deck_ids: Array, filter: Dictionary, request, subtitle_text: String = "") -> void:
\t_multi = true
\t_selection = request
\t_selected_ids.clear()
\tvar matching: Array = []
\tfor id in deck_ids:
\t\tif CARD_FILTER.matches(CARD_FILTER.card_by_id(int(id)), filter):
\t\t\tmatching.append(int(id))
\tmatching.sort_custom(func(a, b): return _sort_key(a) < _sort_key(b))
\t_matching = matching
\t_page = 0
\t_title.text = "Choose cards"
\t_subtitle.text = subtitle_text if subtitle_text != "" else _subtitle_for(filter)
\t_status.text = "Select up to %d." % int(request.maximum)
\tif _confirm != null:
\t\t_confirm.text = "Confirm"
\t\t_confirm.visible = true
\tif _cancel != null:
\t\t_cancel.text = "Cancel"
\t_rebuild_page()
\t_layout()


''' + anchor
assert anchor in s
s = s.replace(anchor, multi_open, 1)

# 6) _rebuild_page: preserve multi selection; sync visuals.
old = '''\t_cards.clear()
\t# Those tweens belonged to nodes that are being freed.
\t_sliding.clear()
\tselected_id = CHOOSE_NONE
\t_selected_node = null
\t_hovered_index = -1
\tif _confirm != null:
\t\t_confirm.disabled = true

\tvar first: int = _page * PAGE_SIZE
\tvar last: int = mini(first + PAGE_SIZE, _matching.size())
\tfor i in range(first, last):
\t\t_fan.add_child(_make_card(_matching[i]))
'''
new = '''\t_cards.clear()
\t# Those tweens belonged to nodes that are being freed.
\t_sliding.clear()
\tif _multi:
\t\t# The ids survive a page turn; only the visible copy map is rebuilt.
\t\t_selected_node = null
\t\t_node_selected.clear()
\t\t_hovered_index = -1
\telse:
\t\tselected_id = CHOOSE_NONE
\t\t_selected_node = null
\t\t_hovered_index = -1
\t\tif _confirm != null:
\t\t\t_confirm.disabled = true

\tvar first: int = _page * PAGE_SIZE
\tvar last: int = mini(first + PAGE_SIZE, _matching.size())
\tfor i in range(first, last):
\t\t_fan.add_child(_make_card(_matching[i]))
\tif _multi:
\t\t_sync_multi_visuals()
'''
assert old in s
s = s.replace(old, new, 1)

# 7) _hover / _unhover
old = '''func _hover(_id: int, node: Control) -> void:
\tif node == null:
\t\treturn
\tif node != _selected_node:
\t\tCARD_VIEW.set_aura(node, true, CARD_VIEW.HOVER_COLOUR)
\t# Remember which card is under the pointer: it is the one that grows, and nothing else moves.
\t_hovered_index = node.get_index()
\t_place_cards()


func _unhover() -> void:
\tfor id in _cards:
\t\tfor node in _cards[id]:
\t\t\tif node != _selected_node:
\t\t\t\tCARD_VIEW.set_aura(node, false, CARD_VIEW.HOVER_COLOUR)
\t# ...and the row settles back, with nothing left enlarged.
\t_hovered_index = -1
\t_place_cards()
'''
new = '''func _hover(_id: int, node: Control) -> void:
\tif node == null:
\t\treturn
\tif _multi:
\t\tif bool(_node_selected.get(node, false)):
\t\t\t_hovered_index = node.get_index()
\t\t\t_place_cards()
\t\t\treturn
\t\tif _selection == null or not _selection.allows(_id, _selected_ids):
\t\t\treturn
\tif node != _selected_node:
\t\tCARD_VIEW.set_aura(node, true, CARD_VIEW.HOVER_COLOUR)
\t# Remember which card is under the pointer: it is the one that grows, and nothing else moves.
\t_hovered_index = node.get_index()
\t_place_cards()


func _unhover() -> void:
\tfor id in _cards:
\t\tfor node in _cards[id]:
\t\t\tif _multi:
\t\t\t\tif not bool(_node_selected.get(node, false)):
\t\t\t\t\tCARD_VIEW.set_aura(node, false, CARD_VIEW.HOVER_COLOUR)
\t\t\telif node != _selected_node:
\t\t\t\tCARD_VIEW.set_aura(node, false, CARD_VIEW.HOVER_COLOUR)
\t# ...and the row settles back, with nothing left enlarged.
\t_hovered_index = -1
\t_place_cards()
'''
assert old in s
s = s.replace(old, new, 1)

# 8) _select multi branch
old = '''func _select(id: int, node: Control) -> void:
\t# Clicking the card that is ALREADY selected de-selects it'''
new = '''func _select(id: int, node: Control) -> void:
\tif _multi:
\t\t_toggle_multi(id)
\t\treturn
\t# Clicking the card that is ALREADY selected de-selects it'''
assert old in s
s = s.replace(old, new, 1)

# 9) Replace _finish with confirm + multi helpers
old = '''func _finish(chosen_id: int) -> void:
\tfinished.emit(chosen_id)
\tqueue_free()
'''
new = '''func _confirm_pressed() -> void:
\tif _multi:
\t\tif _selection == null or not _selection.valid(_selected_ids):
\t\t\treturn
\t\tfinished_multi.emit(_selected_ids.duplicate())
\t\tqueue_free()
\t\treturn
\t_finish(selected_id)


func _finish(chosen_id: int) -> void:
\tfinished.emit(chosen_id)
\tqueue_free()


## Toggle one copy of `id`. The selected list can hold the same id twice: a total-cost constraint may allow two
## copies of one card, while a unique-element constraint will block the second copy.
func _toggle_multi(id: int) -> void:
\tif _selected_ids.has(id):
\t\t_selected_ids.erase(id)
\telse:
\t\tif _selection == null or not _selection.allows(id, _selected_ids):
\t\t\treturn
\t\t_selected_ids.append(id)
\t_rebuild_page()
\t_layout()


## Recompute orange/dim states for the visible page. Selected copies are marked in list order; all other cards
## are checked against the live constraints. This is the single place the dark overlay is applied.
func _sync_multi_visuals() -> void:
\tif not _multi or _selection == null:
\t\treturn
\tvar remaining: Dictionary = {}
\tfor id in _selected_ids:
\t\tremaining[id] = int(remaining.get(id, 0)) + 1
\tfor node in _fan.get_children():
\t\tvar id: int = _id_of(node)
\t\tif id == CHOOSE_NONE:
\t\t\tcontinue
\t\tvar left: int = int(remaining.get(id, 0))
\t\tif left > 0:
\t\t\tremaining[id] = left - 1
\t\t\t_node_selected[node] = true
\t\t\tCARD_VIEW.set_unavailable(node, false)
\t\t\tCARD_VIEW.set_aura(node, true, CARD_VIEW.SELECTED_COLOUR)
\t\t\tnode.mouse_filter = Control.MOUSE_FILTER_STOP
\t\telse:
\t\t\t_node_selected[node] = false
\t\t\tvar allowed: bool = _selection.allows(id, _selected_ids)
\t\t\tCARD_VIEW.set_aura(node, false, CARD_VIEW.HOVER_COLOUR)
\t\t\tCARD_VIEW.set_unavailable(node, not allowed)
\t\t\tnode.mouse_filter = Control.MOUSE_FILTER_STOP if allowed else Control.MOUSE_FILTER_IGNORE
\tif _confirm != null:
\t\t_confirm.disabled = not _selection.valid(_selected_ids)
\t_status.text = "Selected %d. Confirm to play." % _selected_ids.size() if not _selected_ids.is_empty() \
\t\telse "Nothing selected. Cancel to take no cards."
'''
assert old in s
s = s.replace(old, new, 1)

p.write_text(s, encoding='utf-8', newline='\n')
print('deck search multi-select added')
